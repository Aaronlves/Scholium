import ScholiumContracts
import SwiftUI

/// Machine-local evidence for mutations made through Scholium's MCP surface.
/// This view does not represent conversation, review, acceptance, or Settlement.
struct AgentChangesView: View {
    typealias Loader = @MainActor () async throws -> [AgentChange]
    typealias ReviewLoader = @MainActor (UUID) async throws -> AgentChangeReview
    typealias Undo = @MainActor (AgentChange) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    let load: Loader
    let loadReview: ReviewLoader
    let undo: Undo

    @State private var changes: [AgentChange] = []
    @State private var selectedIndex: Int?
    @State private var review: AgentChangeReview?
    @State private var isLoading = true
    @State private var isLoadingReview = false
    @State private var undoingID: UUID?
    @State private var pendingUndo: AgentChange?
    @State private var errorMessage: String?
    @State private var reviewErrorMessage: String?

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Agent Changes",
            detail: "Inspect one exact machine-local MCP mutation at a time.",
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
        .task { await reload() }
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
                detail: Text("Successful MCP mutations will appear here."),
                indicator: .symbol("sparkles")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if let selectedIndex, !changes.isEmpty {
            HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
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

                Spacer(minLength: 0)

                if let review, review.change.operation == .update,
                   review.change.state == .confirmed {
                    VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Button(undoingID == review.change.id ? "Undoing…" : "Undo") {
                            pendingUndo = review.change
                        }
                        .scholiumActivationPointer()
                        .buttonStyle(.bordered)
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
            changes = try await load().sorted(by: Self.precedesInConfirmationOrder)
            if changes.isEmpty {
                selectedIndex = nil
                review = nil
            } else {
                selectedIndex = selectedID.flatMap { id in
                    changes.firstIndex(where: { $0.id == id })
                } ?? changes.indices.last
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
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                Label(operationTitle, systemImage: operationSymbol)
                    .font(ScholiumTypography.interface(.sectionTitle))
                Spacer(minLength: 0)
                Text(review.change.createdAt, format: .dateTime)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Text(displayName)
                .font(ScholiumTypography.scholarly(.title))
                .textSelection(.enabled)
            if let revisionStateTitle {
                Text(revisionStateTitle)
                    .font(ScholiumTypography.interface(.body, emphasis: .strong))
                    .scholiumForeground(revisionStateColor)
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
        case .update:
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
                        .background(ScholiumColorRole.documentBackground.color)
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
            ScholiumApparatusFactGrid(facts: technicalFacts)
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
        review.change.finalRelativePath
            ?? review.change.originalRelativePath
            ?? review.change.noteID.uuidString.lowercased()
    }

    private var displayName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private var operationTitle: LocalizedStringResource {
        switch review.change.operation {
        case .create: "Created by External Agent"
        case .update: "Updated by External Agent"
        case .trash: "Moved to System Trash"
        }
    }

    private var operationSymbol: String {
        switch review.change.operation {
        case .create: "doc.badge.plus"
        case .update: "pencil"
        case .trash: "trash"
        }
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
