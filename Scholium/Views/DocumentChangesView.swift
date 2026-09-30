import ScholiumContracts
import SwiftUI

enum DocumentChangesScope: Hashable {
    case all
    case note(UUID)
    case notes([UUID])

    var identity: String {
        switch self {
        case .all: "all"
        case .note(let id): "note:\(id)"
        case .notes(let ids): "notes:\(ids.map(\.uuidString).sorted().joined(separator: ","))"
        }
    }

    func contains(_ noteID: UUID) -> Bool {
        switch self {
        case .all: true
        case .note(let id): id == noteID
        case .notes(let ids): ids.contains(noteID)
        }
    }

    static func noteIDs(
        forReceiptIDs ids: [UUID],
        in receipts: [AgentChange]
    ) -> [UUID] {
        let selected = Set(ids)
        let affected = receipts.filter { selected.contains($0.id) }.flatMap { receipt in
            [receipt.noteID] + (receipt.moveEffects ?? []).map(\.noteID)
        }
        return Array(Set(affected)).sorted { $0.uuidString < $1.uuidString }
    }
}

enum DocumentChangesPage: String, CaseIterable {
    case pending
    case history
}

/// A sheet keeps the capability chosen when it opened. A later workspace
/// switch cannot retarget a pending acknowledgement or history deletion.
struct DocumentChangesRouteBinding: Sendable {
    let runtimeIdentity: TriptychRuntimeIdentity
    let operations: any DocumentChangeUseCases

    func requireCurrent(
        _ current: TriptychRuntimeIdentity?
    ) throws -> any DocumentChangeUseCases {
        guard current == runtimeIdentity else {
            throw DocumentChangeError.unavailable(
                "The Triptych changed. Close and reopen Changes."
            )
        }
        return operations
    }
}

/// Current saved Note comparisons and explicitly reviewed batches. Receipt
/// evidence has its own route and does not own this review state.
struct DocumentChangesView: View {
    private struct DeleteTarget {
        let id: UUID
        let path: String
    }

    typealias PendingLoader = @MainActor () async throws -> [DocumentChangeSummary]
    typealias ReviewLoader = @MainActor (UUID) async throws -> DocumentChangeReview
    typealias HistoryLoader = @MainActor () async throws -> [ReviewedDocumentChange]
    typealias HistoryDetailLoader = @MainActor (UUID) async throws -> ReviewedDocumentChangeDetail
    typealias Marker = @MainActor (DocumentChangeCapture) async throws -> ReviewedDocumentChange
    typealias DeleteHistory = @MainActor (UUID) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    let scope: DocumentChangesScope
    let invalidationRevision: UInt64
    let loadPending: PendingLoader
    let loadReview: ReviewLoader
    let loadHistory: HistoryLoader
    let loadHistoryDetail: HistoryDetailLoader
    let markReviewed: Marker
    let deleteHistory: DeleteHistory
    let didChange: @MainActor () -> Void

    @State private var page: DocumentChangesPage = .pending
    @State private var pending: [DocumentChangeSummary] = []
    @State private var history: [ReviewedDocumentChange] = []
    @State private var selectedNoteID: UUID?
    @State private var selectedBatchID: UUID?
    @State private var review: DocumentChangeReview?
    @State private var historyDetail: ReviewedDocumentChangeDetail?
    @State private var showingDetail = false
    @State private var isLoading = true
    @State private var isLoadingDetail = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var detailErrorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var pendingDelete: DeleteTarget?
    @State private var differenceIndex: Int?
    @State private var updatedWhileOpen = false
    @State private var reloadGeneration: UInt64 = 0
    @State private var detailGeneration: UInt64 = 0

    private var visiblePending: [DocumentChangeSummary] {
        pending.filter { scope.contains($0.noteID) }
    }

    private var visibleHistory: [ReviewedDocumentChange] {
        history.filter { scope.contains($0.noteID) }
    }

    private var differences: [Int] {
        let comparison = page == .pending ? review?.comparison : historyDetail?.comparison
        return comparison.map {
            ExactSourceComparisonPresentation.differenceStartLineIDs(lines: $0.lines)
        } ?? []
    }

    private var detailReady: Bool {
        showingDetail && !isLoading && !isLoadingDetail
            && errorMessage == nil && detailErrorMessage == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScholiumStructuralRule()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScholiumStructuralRule()
            footer
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.AgentChanges.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.AgentChanges.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.AgentChanges.minimumHeight,
            idealHeight: ScholiumMetrics.ResearchSheet.AgentChanges.idealHeight
        )
        .presentationSizing(.fitted)
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .interactiveDismissDisabled(isMutating)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scholium.changes")
        .task { await reload() }
        .onChange(of: scope.identity) { _, _ in
            reloadGeneration &+= 1
            detailGeneration &+= 1
            selectedNoteID = nil
            selectedBatchID = nil
            review = nil
            historyDetail = nil
            showingDetail = false
            differenceIndex = nil
            updatedWhileOpen = false
            Task { await reload() }
        }
        .onChange(of: page) { _, _ in
            let shouldReload = updatedWhileOpen
            showingDetail = false
            detailErrorMessage = nil
            actionErrorMessage = nil
            differenceIndex = nil
            if shouldReload { Task { await reload() } }
        }
        .onChange(of: invalidationRevision) { _, _ in
            if showingDetail {
                updatedWhileOpen = true
            } else {
                Task { await reload() }
            }
        }
        .confirmationDialog(
            "Delete Reviewed Record?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete Record", role: .destructive) {
                guard let target = pendingDelete else { return }
                pendingDelete = nil
                Task { await deleteReviewedRecord(target.id) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(
                "The reviewed comparison for \(pendingDelete?.path ?? "") will be deleted on this Mac. Current Note text and pending Changes remain available.")
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Changes").font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityHeading(.h1)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                pagePicker
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Changes").font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityHeading(.h1)
                pagePicker
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    private var pagePicker: some View {
        Picker("Changes", selection: $page) {
            Text("Pending Changes").tag(DocumentChangesPage.pending)
            Text("History").tag(DocumentChangesPage.history)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("scholium.changes.page")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading Changes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            stateWithRetry("Changes Unavailable", message: errorMessage) {
                Task { await reload() }
            }
        } else if showingDetail {
            if isLoadingDetail {
                ProgressView("Loading Comparison…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detailErrorMessage {
                stateWithRetry("Comparison Unavailable", message: detailErrorMessage) {
                    Task { await loadSelectedDetail() }
                }
            } else if page == .pending, let review {
                comparisonContent(
                    path: review.summary.relativePath,
                    comparison: review.comparison,
                    baselineState: review.summary.baselineState,
                    endingSource: review.endingSource,
                    detail: review.summary.savedAt
                )
            } else if page == .history, let historyDetail {
                comparisonContent(
                    path: historyDetail.batch.relativePath,
                    comparison: historyDetail.comparison,
                    baselineState: historyDetail.batch.wasNewDocument ? .newDocument : .known,
                    endingSource: historyDetail.endingSource,
                    detail: historyDetail.batch.reviewedAt
                )
            }
        } else if page == .pending {
            if visiblePending.isEmpty {
                ScholiumContentStateView(
                    "No Pending Changes",
                    detail: Text("Saved Notes with changes to review will appear here."),
                    indicator: .symbol("checkmark.circle")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                pendingTable
            }
        } else if visibleHistory.isEmpty {
            ScholiumContentStateView(
                "No Reviewed History",
                detail: Text("Reviewed Note comparisons will appear here."),
                indicator: .symbol("clock")
            ).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            historyTable
        }
    }

    private var pendingTable: some View {
        NativeResearchTable(
            columns: [
                .init(id: "note", title: ScholiumL10n.string("Note")),
                .init(
                    id: "saved", title: ScholiumL10n.string("Saved"),
                    width: ScholiumMetrics.ResearchSheet.AgentChanges.dateColumnWidth,
                    secondary: true),
            ],
            rows: visiblePending.map { item in
                .init(
                    id: item.noteID.uuidString,
                    cells: [
                        displayName(item.relativePath),
                        item.savedAt?.formatted(.dateTime.month().day().hour().minute()) ?? "—",
                    ], help: item.relativePath)
            },
            selection: Binding(
                get: { selectedNoteID?.uuidString },
                set: { selectedNoteID = $0.flatMap(UUID.init(uuidString:)) }
            ),
            accessibilityLabel: ScholiumL10n.string("Pending Changes"),
            identifier: "scholium.changes.pending",
            primaryAction: { id in
                guard let noteID = UUID(uuidString: id) else { return }
                openPending(noteID)
            }
        )
    }

    private var historyTable: some View {
        NativeResearchTable(
            columns: [
                .init(id: "note", title: ScholiumL10n.string("Note")),
                .init(
                    id: "reviewed", title: ScholiumL10n.string("Reviewed"),
                    width: ScholiumMetrics.ResearchSheet.AgentChanges.dateColumnWidth,
                    secondary: true),
            ],
            rows: visibleHistory.map { item in
                .init(
                    id: item.id.uuidString,
                    cells: [
                        displayName(item.relativePath),
                        item.reviewedAt.formatted(.dateTime.month().day().hour().minute()),
                    ], help: item.relativePath)
            },
            selection: Binding(
                get: { selectedBatchID?.uuidString },
                set: { selectedBatchID = $0.flatMap(UUID.init(uuidString:)) }
            ),
            accessibilityLabel: ScholiumL10n.string("Reviewed History"),
            identifier: "scholium.changes.history",
            primaryAction: { id in
                guard let batchID = UUID(uuidString: id) else { return }
                openHistory(batchID)
            }
        )
    }

    private func comparisonContent(
        path: String,
        comparison: ExactSourceComparison?,
        baselineState: DocumentChangeBaselineState,
        endingSource: String,
        detail: Date?
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                    VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
                        Text(displayName(path)).font(.headline).textSelection(.enabled)
                        if let detail {
                            Text(detail, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .help(path)
                    if updatedWhileOpen {
                        Text("Changes were updated elsewhere. This comparison still shows the saved version opened here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let comparison {
                        ExactSourceComparisonView(
                            comparison: comparison,
                            startingLabel: "Before",
                            endingLabel: "After",
                            startingOnlyLabel: "Removed",
                            endingOnlyLabel: "Inserted",
                            identifierPrefix: "scholium.changes"
                        )
                    } else {
                        baselineMessage(baselineState)
                        Text(verbatim: endingSource)
                            .font(ScholiumTypography.exact(.body))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(ScholiumGrid.Spacing.nestedContentInset)
                            .background(ScholiumNativeColorRole.textBackground.color)
                            .accessibilityIdentifier("scholium.changes.currentSource")
                    }
                }
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: differenceIndex) { _, index in
                guard let index, differences.indices.contains(index) else { return }
                proxy.scrollTo(differences[index], anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func baselineMessage(_ state: DocumentChangeBaselineState) -> some View {
        switch state {
        case .newDocument:
            Text("New Note — no earlier reviewed version")
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("The earlier saved version is unavailable. The displayed saved source is shown without an invented comparison.")
                .foregroundStyle(.secondary)
        case .known:
            Text("The exact comparison is unavailable. The saved ending source is shown.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if let actionErrorMessage {
                Label(actionErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
                    leadingFooterControls
                    Spacer(minLength: 0)
                    trailingFooterControls
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    HStack {
                        leadingFooterControls
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        trailingFooterControls
                    }
                }
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    private var leadingFooterControls: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            if showingDetail {
                Button("Back") {
                    let shouldReload = updatedWhileOpen
                    showingDetail = false
                    differenceIndex = nil
                    if shouldReload { Task { await reload() } }
                }.disabled(isMutating)
                if detailReady && !differences.isEmpty {
                    differenceNavigation
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trailingFooterControls: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            if isMutating { ProgressView().controlSize(.small) }
            if page == .history, detailReady, let historyDetail {
                Menu {
                    Button("Delete from History", role: .destructive) {
                        pendingDelete = DeleteTarget(
                            id: historyDetail.batch.id,
                            path: historyDetail.batch.relativePath
                        )
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .disabled(isMutating)
                .accessibilityIdentifier("scholium.changes.historyActions")
            }
            Button("Close", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
                .disabled(isMutating)
            if page == .pending, detailReady, let review {
                Button("Mark as Reviewed") {
                    Task { await markCurrentReview(review.capture) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isMutating)
                .help("Marks only the displayed saved revision as reviewed. Later saved changes remain pending.")
                .accessibilityIdentifier("scholium.changes.markReviewed")
            } else if !showingDetail {
                Button("View Changes") {
                    if page == .pending, let selectedNoteID { openPending(selectedNoteID) }
                    if page == .history, let selectedBatchID { openHistory(selectedBatchID) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(page == .pending ? selectedNoteID == nil : selectedBatchID == nil)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var differenceNavigation: some View {
        ControlGroup {
            Button {
                differenceIndex = max(0, (differenceIndex ?? differences.count) - 1)
            } label: {
                Label("Previous Difference", systemImage: "chevron.up")
            }
            .disabled(differenceIndex == nil || differenceIndex == 0)
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .accessibilityIdentifier("scholium.changes.previousDifference")
            Button {
                differenceIndex = min(differences.count - 1, (differenceIndex ?? -1) + 1)
            } label: {
                Label("Next Difference", systemImage: "chevron.down")
            }
            .disabled(differenceIndex == differences.count - 1)
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .accessibilityIdentifier("scholium.changes.nextDifference")
        }
        .labelStyle(.iconOnly)
        .fixedSize()
        .accessibilityValue(Text("\((differenceIndex ?? -1) + 1) of \(differences.count) differences"))
    }

    private func stateWithRetry(
        _ title: LocalizedStringResource,
        message: String,
        retry: @escaping () -> Void
    ) -> some View {
        VStack(spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
            ScholiumContentStateView(
                title, detail: Text(verbatim: message),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            )
            Button("Retry", action: retry)
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let scopeIdentity = scope.identity
        isLoading = true
        updatedWhileOpen = false
        errorMessage = nil
        do {
            async let newPending = loadPending()
            async let newHistory = loadHistory()
            let (loadedPending, loadedHistory) = try await (newPending, newHistory)
            guard generation == reloadGeneration, scope.identity == scopeIdentity else { return }
            pending = loadedPending
            history = loadedHistory
            if case .note(let id) = scope, page == .pending,
                visiblePending.contains(where: { $0.noteID == id })
            {
                openPending(id)
            } else {
                showingDetail = false
            }
            if !visiblePending.contains(where: { $0.noteID == selectedNoteID }) {
                selectedNoteID = visiblePending.first?.noteID
            }
            if !visibleHistory.contains(where: { $0.id == selectedBatchID }) {
                selectedBatchID = visibleHistory.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration, scope.identity == scopeIdentity else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openPending(_ noteID: UUID) {
        guard visiblePending.contains(where: { $0.noteID == noteID }) else { return }
        selectedNoteID = noteID
        review = nil
        showingDetail = true
        differenceIndex = nil
        updatedWhileOpen = false
        Task { await loadSelectedDetail() }
    }

    private func openHistory(_ batchID: UUID) {
        guard visibleHistory.contains(where: { $0.id == batchID }) else { return }
        selectedBatchID = batchID
        historyDetail = nil
        showingDetail = true
        differenceIndex = nil
        updatedWhileOpen = false
        Task { await loadSelectedDetail() }
    }

    private func loadSelectedDetail() async {
        detailGeneration &+= 1
        let generation = detailGeneration
        let scopeIdentity = scope.identity
        isLoadingDetail = true
        detailErrorMessage = nil
        let selectedPage = page
        let selectedID = selectedPage == .pending ? selectedNoteID : selectedBatchID
        guard let selectedID else {
            isLoadingDetail = false
            return
        }
        do {
            if selectedPage == .pending {
                let loaded = try await loadReview(selectedID)
                guard generation == detailGeneration, scope.identity == scopeIdentity,
                    page == selectedPage, selectedNoteID == selectedID,
                    loaded.summary.noteID == selectedID,
                    loaded.capture.noteID == selectedID
                else { return }
                review = loaded
            } else {
                let loaded = try await loadHistoryDetail(selectedID)
                guard generation == detailGeneration, scope.identity == scopeIdentity,
                    page == selectedPage, selectedBatchID == selectedID,
                    loaded.batch.id == selectedID
                else { return }
                historyDetail = loaded
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == detailGeneration, scope.identity == scopeIdentity,
                page == selectedPage
            else { return }
            detailErrorMessage = error.localizedDescription
        }
        if generation == detailGeneration, page == selectedPage { isLoadingDetail = false }
    }

    private func markCurrentReview(_ capture: DocumentChangeCapture) async {
        guard review?.capture == capture else { return }
        let scopeIdentity = scope.identity
        isMutating = true
        actionErrorMessage = nil
        do {
            _ = try await markReviewed(capture)
            didChange()
            guard scope.identity == scopeIdentity else {
                isMutating = false
                return
            }
            review = nil
            showingDetail = false
            await reload()
        } catch {
            if scope.identity == scopeIdentity { actionErrorMessage = error.localizedDescription }
        }
        isMutating = false
    }

    private func deleteReviewedRecord(_ id: UUID) async {
        let scopeIdentity = scope.identity
        isMutating = true
        actionErrorMessage = nil
        do {
            try await deleteHistory(id)
            didChange()
            guard scope.identity == scopeIdentity else {
                isMutating = false
                return
            }
            historyDetail = nil
            selectedBatchID = nil
            showingDetail = false
            await reload()
        } catch {
            if scope.identity == scopeIdentity {
                let issue = error.localizedDescription
                historyDetail = nil
                showingDetail = false
                await reload()
                actionErrorMessage = issue
            }
        }
        isMutating = false
    }

    private func displayName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
