import ScholiumContracts
import SwiftUI

enum AgentChangePresentation {
    static func path(for change: AgentChange) -> String {
        change.finalRelativePath
            ?? change.originalRelativePath
            ?? change.noteID.uuidString.lowercased()
    }

    static func displayName(for change: AgentChange) -> String {
        let path = path(for: change)
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    static func operationTitle(
        for operation: AgentChangeOperation
    ) -> LocalizedStringResource {
        switch operation {
        case .create: "Created by External Agent"
        case .update: "Updated by External Agent"
        case .metadata: "Metadata"
        case .attachment: "Attachments"
        case .trash: "Moved to System Trash"
        case .move: "Moved by External Agent"
        }
    }

    static func shortOperationTitle(for operation: AgentChangeOperation) -> LocalizedStringResource {
        switch operation {
        case .create: "Created"
        case .update, .metadata, .attachment: "Edited"
        case .trash: "Moved to Trash"
        case .move: "Moved"
        }
    }

    static func operationSymbol(for operation: AgentChangeOperation) -> String {
        switch operation {
        case .create: "doc.badge.plus"
        case .update, .metadata, .attachment: "pencil"
        case .trash: "trash"
        case .move: "folder"
        }
    }

    static func stateTitle(
        for change: AgentChange,
        endingRevisionState: AgentChangeEndingRevisionState?
    ) -> LocalizedStringResource {
        switch change.state {
        case .prepared:
            "Prepared"
        case .outcomeUncertain:
            "Outcome uncertain — inspect current source before retrying."
        case .undone:
            "This update was undone."
        case .confirmed:
            switch endingRevisionState {
            case .current: "Current Revision"
            case .earlierRevision: "Earlier Revision"
            case .unavailable, nil: "Current Source Unavailable"
            }
        }
    }

    /// Presentation only: older exact evidence remains available by its receipt ID.
    static func latestPerNote(_ changes: [AgentChange]) -> [AgentChange] {
        var seen = Set<UUID>()
        return changes.sorted(by: newestFirst).filter { seen.insert($0.noteID).inserted }
    }

    static func inScope(_ changes: [AgentChange], scope: AgentChangesScope) -> [AgentChange] {
        switch scope {
        case .exact(let id): return changes.filter { $0.id == id }
        case .conversation(let ids):
            let selected = Set(ids)
            return changes.filter { selected.contains($0.id) }
        case .current: return latestPerNote(changes)
        }
    }

    static func newestFirst(_ lhs: AgentChange, _ rhs: AgentChange) -> Bool {
        let lhsDate = lhs.confirmedAt ?? lhs.createdAt
        let rhsDate = rhs.confirmedAt ?? rhs.createdAt
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Machine-local evidence for mutations made through Scholium's MCP surface.
/// This view does not represent conversation, review, acceptance, or Settlement.
struct AgentChangesView: View {
    typealias Loader = @MainActor () async throws -> [AgentChange]
    typealias ReviewLoader = @MainActor (UUID) async throws -> AgentChangeReview
    typealias Undo = @MainActor (AgentChange) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AgentChangeViewedLedger.key) private var viewedChangeData = Data()
    let scope: AgentChangesScope
    private var initialChangeID: UUID? { scope.exactID }
    let load: Loader
    let loadReview: ReviewLoader
    let undo: Undo

    @State private var changes: [AgentChange] = []
    @State private var showsCollection = true
    @State private var selectedIndex: Int?
    @State private var review: AgentChangeReview?
    @State private var isLoading = true
    @State private var isLoadingReview = false
    @State private var undoingID: UUID?
    @State private var pendingUndo: AgentChange?
    @State private var errorMessage: String?
    @State private var reviewErrorMessage: String?

    private var presentsCollection: Bool {
        showsCollection || isLoading || errorMessage != nil || changes.isEmpty
    }

    private var sheetSize: NSSize {
        presentsCollection
            ? NSSize(width: 620, height: isLoading || errorMessage != nil || changes.isEmpty
                     ? 240 : min(480, 100 + CGFloat(changes.count) * 76))
            : NSSize(width: 760, height: 720)
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentsCollection {
                collectionLayout
            } else {
                ExactSourceComparisonSheetLayout(
                    title: { if case .conversation = scope { return "Conversation Changes" }; return "Agent Changes" }(),
                    detail: nil,
                    identifier: "scholium.agentChanges"
                ) {
                    Button("Close", action: dismiss.callAsFunction)
                        .scholiumActivationPointer()
                        .keyboardShortcut(.cancelAction)
                } content: {
                    content
                } footer: {
                    footer
                }
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(AgentChangesSheetSize(size: sheetSize))
        .task { showsCollection = initialChangeID == nil; await reload(preserving: initialChangeID) }
        .confirmationDialog(
            "Undo Agent Change?",
            isPresented: Binding(
                get: { pendingUndo != nil },
                set: { if !$0 { pendingUndo = nil } }
            ),
            presenting: pendingUndo
        ) { change in
            Button("Restore Before Version", role: .destructive) {
                pendingUndo = nil
                Task { await undoChange(change) }
            }
            .scholiumActivationPointer()
            Button("Cancel", role: .cancel) { pendingUndo = nil }
            .scholiumActivationPointer()
        } message: { _ in
            Text("Undo restores the exact Before version only if the Note still matches this change's After version.")
        }
    }

    private var collectionLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text({ if case .conversation = scope { return String(localized: "Conversation Changes") }
                       return String(localized: "Agent Changes") }())
                    .font(ScholiumTypography.interface(.sectionTitle)).accessibilityHeading(.h1)
                Spacer()
                Button("Close", action: dismiss.callAsFunction).keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .accessibilityIdentifier("scholium.agentChanges")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading Agent Changes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ScholiumContentStateView(
                "Agent Changes Unavailable",
                detail: Text(errorMessage),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if changes.isEmpty {
            ScholiumContentStateView(
                "No Agent Changes",
                detail: Text("Notes changed by an Agent will appear here."),
                indicator: .symbol("sparkles")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showsCollection {
            let ordered = changes.sorted(by: AgentChangePresentation.newestFirst)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ordered) { change in
                        Button {
                            showsCollection = false
                            if let index = changes.firstIndex(where: { $0.id == change.id }) { select(index) }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: AgentChangePresentation.operationSymbol(for: change.operation))
                                    .scholiumForeground(.secondaryText).frame(width: 24)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AgentChangePresentation.displayName(for: change))
                                        .font(ScholiumTypography.interface(.sectionTitle)).scholiumForeground(.primaryText).lineLimit(2)
                                    HStack(spacing: 8) {
                                        Text(AgentChangePresentation.shortOperationTitle(for: change.operation))
                                        if change.state == .undone { Text("Undone") }
                                        if AgentChangeViewedLedger(data: viewedChangeData).ids.contains(change.id) { Text("Viewed") }
                                    }.font(ScholiumTypography.interface(.small)).scholiumForeground(.secondaryText)
                                }
                                Spacer(minLength: 12)
                                Text(change.confirmedAt ?? change.createdAt, format: .dateTime.month().day().hour().minute())
                                    .font(ScholiumTypography.interface(.small)).scholiumForeground(.secondaryText)
                                Image(systemName: "chevron.right").imageScale(.small).scholiumForeground(.secondaryText)
                            }
                            .padding(.vertical, 16).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scholium.agentChanges.open.\(change.id.uuidString)")
                        if change.id != ordered.last?.id { Divider() }
                    }
                }
            }
        } else if isLoadingReview {
            ProgressView("Loading Exact Change…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let reviewErrorMessage {
            ScholiumContentStateView(
                "Change Unavailable",
                detail: Text(reviewErrorMessage),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let review {
            AgentChangeReviewContent(review: review)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !showsCollection, let selectedIndex, !changes.isEmpty {
            HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
                if initialChangeID == nil {
                    Button("All Changes") { showsCollection = true }
                        .disabled(undoingID != nil)

                    Button("Previous") { select(selectedIndex - 1) }
                        .scholiumActivationPointer()
                        .disabled(selectedIndex == 0 || isLoadingReview || undoingID != nil)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                        .accessibilityIdentifier("scholium.agentChanges.previous")

                    Text("Change \(selectedIndex + 1) of \(changes.count)")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                        .accessibilityIdentifier("scholium.agentChanges.position")

                    Button("Next") { select(selectedIndex + 1) }
                        .scholiumActivationPointer()
                        .disabled(
                            selectedIndex == changes.count - 1
                                || isLoadingReview || undoingID != nil
                        )
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                        .accessibilityIdentifier("scholium.agentChanges.next")
                }

                Spacer(minLength: 0)

                if let review, review.change.state == .confirmed {
                    let viewed = AgentChangeViewedLedger(data: viewedChangeData).ids.contains(review.change.id)
                    Button(viewed ? "Mark as Unviewed" : "Mark as Viewed") {
                        var ledger = AgentChangeViewedLedger(data: viewedChangeData)
                        ledger.setViewed(!viewed, id: review.change.id)
                        viewedChangeData = ledger.data
                    }
                    .disabled(undoingID != nil)
                    .accessibilityIdentifier("scholium.agentChanges.markViewed")
                }

                if let review, (review.change.operation == .update || review.change.operation.isRecordMutation),
                   review.change.state == .confirmed {
                    VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Button(undoingID == review.change.id ? "Undoing…" : "Undo") {
                            pendingUndo = review.change
                        }
                        .scholiumActivationPointer()
                        .scholiumButtonStyle(.bordered)
                        .disabled(!review.isDirectUndoAvailable || undoingID != nil)
                        .accessibilityHint(
                            review.isDirectUndoAvailable
                                ? "Restores the exact Before version"
                                : "Unavailable because the Note no longer matches this change's After version"
                        )
                        .accessibilityIdentifier(
                            "scholium.agentChanges.undo.\(review.change.id.uuidString.lowercased())"
                        )
                        if !review.isDirectUndoAvailable {
                            Text("Undo is unavailable because the current Note no longer matches this change's After version.")
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
        } else {
            EmptyView()
        }
    }

    private func reload(preserving selectedID: UUID? = nil) async {
        isLoading = true
        errorMessage = nil
        reviewErrorMessage = nil
        do {
            let loaded = try await load()
            changes = AgentChangePresentation.inScope(loaded, scope: scope)
                .sorted(by: Self.precedesInConfirmationOrder)
            if changes.isEmpty {
                selectedIndex = nil
                review = nil
            } else {
                if let selectedID {
                    selectedIndex = changes.firstIndex(where: { $0.id == selectedID })
                    if selectedIndex == nil {
                        review = nil
                        errorMessage = String(localized: "This Agent Change is no longer available.")
                    }
                } else {
                    selectedIndex = changes.indices.last
                }
                await reloadReview()
            }
        } catch {
            errorMessage = error.localizedDescription
            selectedIndex = nil
            review = nil
        }
        isLoading = false
    }

    private func select(_ index: Int) {
        guard changes.indices.contains(index) else { return }
        selectedIndex = index
        review = nil
        reviewErrorMessage = nil
        Task { await reloadReview() }
    }

    private func reloadReview() async {
        guard let selectedIndex, changes.indices.contains(selectedIndex) else { return }
        let selected = changes[selectedIndex]
        isLoadingReview = true
        reviewErrorMessage = nil
        do {
            let loaded = try await loadReview(selected.id)
            guard loaded.change.id == selected.id,
                  loaded.change.noteID == selected.noteID else {
                throw AgentChangeError.mismatchedBinding(selected.id)
            }
            guard self.selectedIndex == selectedIndex else { return }
            review = loaded
        } catch is CancellationError {
            return
        } catch {
            guard self.selectedIndex == selectedIndex else { return }
            review = nil
            reviewErrorMessage = error.localizedDescription
        }
        if self.selectedIndex == selectedIndex { isLoadingReview = false }
    }

    private func undoChange(_ change: AgentChange) async {
        undoingID = change.id
        reviewErrorMessage = nil
        do {
            try await undo(change)
            await reload(preserving: change.id)
        } catch {
            reviewErrorMessage = error.localizedDescription
        }
        undoingID = nil
    }

    private static func precedesInConfirmationOrder(
        _ lhs: AgentChange,
        _ rhs: AgentChange
    ) -> Bool {
        let lhsDate = lhs.confirmedAt ?? lhs.createdAt
        let rhsDate = rhs.confirmedAt ?? rhs.createdAt
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct AgentChangeReviewContent: View {
    let review: AgentChangeReview

    var body: some View {
        ScrollView(.vertical) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
            ) {
                summary
                content
                technicalDetails
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayName).font(ScholiumTypography.interface(.sectionTitle)).textSelection(.enabled)
            HStack(alignment: .firstTextBaseline) {
                Label(AgentChangePresentation.shortOperationTitle(for: review.change.operation), systemImage: operationSymbol)
                Spacer(minLength: 12)
                Text(review.change.createdAt, format: .dateTime)
            }.font(ScholiumTypography.interface(.body)).scholiumForeground(.secondaryText)
            if let revisionStateTitle {
                Text(revisionStateTitle)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(review.endingRevisionState == .current ? .secondaryText : .primaryText)
                    .accessibilityIdentifier("scholium.agentChanges.revisionState")
            }
            if review.change.state == .outcomeUncertain {
                Text("Outcome uncertain — inspect current source before retrying.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
            } else if review.change.state == .undone {
                Text("This update was undone.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch review.change.operation {
        case .update, .move, .metadata, .attachment:
            if review.change.operation == .move {
                Text((review.change.originalRelativePath ?? "") + " → " + (review.change.finalRelativePath ?? "")).textSelection(.enabled)
            }
            if let reason = review.undoUnavailableReason { Text(reason).textSelection(.enabled) }
            ForEach(review.linkedComparisons, id: \.effect.noteID) { linked in
                DisclosureGroup(linked.effect.destination.relativePath) {
                    ExactSourceComparisonView(comparison: linked.comparison, startingLabel: "Before", endingLabel: "After",
                        startingOnlyLabel: "Removed", endingOnlyLabel: "Inserted", identifierPrefix: "scholium.agentChanges.linked")
                }
            }
            if let comparison = review.comparison {
                ExactSourceComparisonView(
                    comparison: comparison,
                    startingLabel: "Before",
                    endingLabel: review.change.state == .prepared
                        || review.change.state == .outcomeUncertain
                        ? "Intended After" : "After",
                    startingOnlyLabel: "Removed",
                    endingOnlyLabel: review.change.state == .prepared
                        || review.change.state == .outcomeUncertain
                        ? "Intended insertion" : "Inserted",
                    identifierPrefix: "scholium.agentChanges"
                )
            } else {
                comparisonUnavailable
            }
        case .create:
            if let source = review.currentCreatedSource {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Text("Current Content")
                        .font(ScholiumTypography.interface(.sectionTitle))
                    Text(source)
                        .font(ScholiumTypography.exact(.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(ScholiumGrid.Spacing.nestedContentInset)
                        .background(ScholiumNativeColorRole.textBackground.color)
                        .clipShape(RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        ))
                }
            } else {
                ScholiumContentStateView(
                    "Created by External Agent",
                    detail: Text("The created revision is not the current Note, so its retained content is not shown as current prose."),
                    indicator: .symbol("doc.badge.plus")
                )
                .frame(
                    minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                )
            }
        case .trash:
            ScholiumContentStateView(
                "Moved to System Trash",
                detail: Text("This change preserves the original Note identity and location. Recovery remains in the Finder-owned system Trash."),
                indicator: .symbol("trash")
            )
            .frame(
                minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
            )
        }
    }

    private var technicalDetails: some View {
        DisclosureGroup("Technical Details") {
            ScholiumApparatusFactList(facts: technicalFacts)
                .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
        }
        .scholiumActivationPointer()
        .font(ScholiumTypography.interface(.body))
    }

    private var comparisonUnavailable: some View {
        ScholiumContentStateView(
            "Comparison Unavailable",
            detail: Text("The exact saved Before and After evidence could not be compared."),
            indicator: .symbol("exclamationmark.triangle", role: .attention)
        )
        .frame(
            minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
        )
    }

    private var technicalFacts: [ScholiumApparatusFact] {
        var facts = [
            ScholiumApparatusFact(
                id: "change-id",
                label: String(localized: "Change ID"),
                value: review.change.id.uuidString.lowercased(),
                valueStyle: .revisionIdentity
            ),
            ScholiumApparatusFact(
                id: "note-id",
                label: String(localized: "Note ID"),
                value: review.change.noteID.uuidString.lowercased(),
                valueStyle: .revisionIdentity
            ),
            ScholiumApparatusFact(
                id: "path",
                label: String(localized: "Path"),
                value: path,
                valueStyle: .exactContent
            ),
        ]
        if let fingerprint = review.change.beforeFingerprint {
            facts.append(ScholiumApparatusFact(
                id: "before-revision",
                label: String(localized: "Before Revision"),
                value: revisionDescription(fingerprint),
                valueStyle: .revisionIdentity
            ))
        }
        if let fingerprint = review.change.afterFingerprint {
            facts.append(ScholiumApparatusFact(
                id: "after-revision",
                label: String(localized: "After Revision"),
                value: revisionDescription(fingerprint),
                valueStyle: .revisionIdentity
            ))
        }
        return facts
    }

    private var path: String {
        AgentChangePresentation.path(for: review.change)
    }

    private var displayName: String {
        AgentChangePresentation.displayName(for: review.change)
    }

    private var operationTitle: LocalizedStringResource {
        AgentChangePresentation.operationTitle(for: review.change.operation)
    }

    private var operationSymbol: String {
        AgentChangePresentation.operationSymbol(for: review.change.operation)
    }

    private var revisionStateTitle: LocalizedStringResource? {
        switch review.endingRevisionState {
        case .current: "Current Revision"
        case .earlierRevision: "Earlier Revision"
        case .unavailable: "Current Source Unavailable"
        case nil: nil
        }
    }

    private var revisionStateColor: ScholiumColorRole {
        review.endingRevisionState == .current ? .confirmed : .attention
    }

    private func revisionDescription(_ fingerprint: DocumentFingerprint) -> String {
        "SHA-256 \(fingerprint.sha256) (\(fingerprint.byteCount) bytes)"
    }
}

/// The sheet's native window owns geometry; content supplies one requested size.
/// Do not resize the workspace or retain a second selection/presentation state.
private struct AgentChangesSheetSize: NSViewRepresentable {
    let size: NSSize
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = resize
        return view
    }
    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        view.onWindowAttachment = resize
        if let window = view.window { resize(window) }
    }
    private func resize(_ window: NSWindow) {
        guard window.sheetParent != nil,
              window.contentRect(forFrameRect: window.frame).size != size else { return }
        window.setContentSize(size)
    }
}
