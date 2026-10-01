import AppKit
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

    static func shortOperationTitle(for operation: AgentChangeOperation) -> LocalizedStringResource {
        switch operation {
        case .create: "Created"
        case .update: "Edited"
        case .trash: "Moved to Trash"
        case .move: "Moved"
        }
    }

    static func operationSymbol(for operation: AgentChangeOperation) -> String {
        switch operation {
        case .create: "doc.badge.plus"
        case .update: "pencil"
        case .trash: "trash"
        case .move: "folder"
        }
    }
}

/// Exact evidence for one MCP operation. This route never acknowledges the
/// cumulative saved-Note comparison or substitutes for Changes History.
struct AgentChangeReceiptView: View {
    typealias ReviewLoader = @MainActor (UUID) async throws -> AgentChangeReview
    typealias Undo = @MainActor (AgentChange) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    let changeID: UUID
    let loadReview: ReviewLoader
    let undo: Undo

    @State private var review: AgentChangeReview?
    @State private var isLoading = true
    @State private var isUndoing = false
    @State private var errorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var pendingUndo: AgentChange?

    var body: some View {
        VStack(spacing: 0) {
            Text("Agent Change Receipt")
                .font(ScholiumTypography.interface(.primaryTitle))
                .accessibilityHeading(.h1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
            ScholiumStructuralRule()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScholiumStructuralRule()
            footer.padding(ScholiumMetrics.ResearchSheet.contentInset)
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
        .interactiveDismissDisabled(isUndoing)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scholium.agentChangeReceipt")
        .task(id: changeID) { await reload() }
        .confirmationDialog(
            "Undo Agent Change?",
            isPresented: Binding(
                get: { pendingUndo != nil },
                set: { if !$0 { pendingUndo = nil } }
            ),
            presenting: pendingUndo
        ) { change in
            if change.operation == .move {
                Button("Restore Original Location and Sources", role: .destructive) {
                    pendingUndo = nil
                    Task { await undoChange(change) }
                }
            } else {
                Button("Restore Before Version", role: .destructive) {
                    pendingUndo = nil
                    Task { await undoChange(change) }
                }
            }
            Button("Cancel", role: .cancel) { pendingUndo = nil }
        } message: { change in
            if change.operation == .move {
                Text(
                    "Undo restores the original Note path and exact Before sources, including linked Note edits, only if the affected saved versions still match this receipt."
                )
            } else {
                Text("Undo restores the exact Before version only if the Note still matches this change's After version.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading Agent Change Receipt…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                ScholiumContentStateView(
                    "Agent Change Receipt Unavailable", detail: Text(verbatim: errorMessage),
                    indicator: .symbol("exclamationmark.triangle", role: .attention)
                )
                Button("Retry") { Task { await reload() } }
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let review {
            AgentChangeReviewContent(review: review)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if let actionErrorMessage {
                Label(actionErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).textSelection(.enabled)
            }
            HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
                if isUndoing {
                    ProgressView().controlSize(.small).accessibilityLabel("Undoing Agent Change")
                }
                Spacer(minLength: 0)
                if let review, !isLoading, errorMessage == nil,
                    review.change.state == .confirmed,
                    review.change.operation == .update || review.change.operation == .move
                {
                    Button(isUndoing ? "Undoing…" : "Undo…") {
                        pendingUndo = review.change
                    }
                    .disabled(!review.isDirectUndoAvailable || isUndoing)
                    .accessibilityHint(
                        review.change.operation == .move
                            ? Text("Restores the original location and exact linked sources when still current")
                            : Text("Restores the exact Before version when still current")
                    )
                    .accessibilityIdentifier("scholium.agentChanges.undo.\(review.change.id.uuidString.lowercased())")
                }
                Button("Close", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isUndoing)
            }
        }
    }

    private func reload() async {
        let requestedID = changeID
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await loadReview(requestedID)
            guard requestedID == changeID else { return }
            guard loaded.change.id == requestedID else {
                throw AgentChangeError.mismatchedBinding(requestedID)
            }
            review = loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestedID == changeID else { return }
            review = nil
            errorMessage = ScholiumErrorLocalization.message(error)
        }
        isLoading = false
    }

    private func undoChange(_ change: AgentChange) async {
        isUndoing = true
        actionErrorMessage = nil
        do {
            try await undo(change)
            await reload()
        } catch {
            actionErrorMessage = ScholiumErrorLocalization.message(error)
        }
        isUndoing = false
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
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
            Text(displayName).font(.headline).textSelection(.enabled)
                .help(AgentChangePresentation.path(for: review.change))
            HStack(alignment: .firstTextBaseline) {
                Label(AgentChangePresentation.shortOperationTitle(for: review.change.operation), systemImage: operationSymbol)
                Spacer(minLength: ScholiumMetrics.ResearchSheet.footerControlSpacing)
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
                Text("This Agent change was undone.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch review.change.operation {
        case .update, .move:
            if review.change.operation == .move {
                Text((review.change.originalRelativePath ?? "") + " → " + (review.change.finalRelativePath ?? "")).textSelection(.enabled)
            }
            if let reason = review.undoUnavailableReason { Text(reason).textSelection(.enabled) }
            ForEach(review.linkedComparisons, id: \.effect.noteID) { linked in
                DisclosureGroup(linked.effect.destination.relativePath) {
                    ExactSourceComparisonView(
                        comparison: linked.comparison, startingLabel: "Before", endingLabel: "After",
                        startingOnlyLabel: "Removed", endingOnlyLabel: "Inserted", identifierPrefix: "scholium.agentChanges.linked"
                    )
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
                        .clipShape(
                            RoundedRectangle(
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

    private var displayName: String {
        AgentChangePresentation.displayName(for: review.change)
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

}
