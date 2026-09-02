import ScholiumContracts
import SwiftUI

/// Machine-local evidence for mutations made through Scholium's MCP surface.
/// This view does not represent conversation, review, acceptance, or Settlement.
struct AgentChangesView: View {
    typealias Loader = @MainActor () async throws -> [AgentChange]
    typealias Undo = @MainActor (AgentChange) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    let load: Loader
    let undo: Undo

    @State private var changes: [AgentChange] = []
    @State private var isLoading = true
    @State private var undoingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Changes")
                        .font(ScholiumTypography.scholarly(.sectionTitle))
                    Text("Exact local evidence for note mutations made through MCP.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                }
                Spacer()
                Button("Close", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)

            Divider()

            Group {
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
                } else {
                    List(changes) { change in
                        AgentChangeRow(
                            change: change,
                            isUndoing: undoingID == change.id,
                            undo: { await undoChange(change) }
                        )
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .task { await reload() }
        .accessibilityIdentifier("scholium.agentChanges")
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            changes = try await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func undoChange(_ change: AgentChange) async {
        undoingID = change.id
        errorMessage = nil
        do {
            try await undo(change)
            changes = try await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        undoingID = nil
    }
}

private struct AgentChangeRow: View {
    let change: AgentChange
    let isUndoing: Bool
    let undo: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(operationTitle, systemImage: operationSymbol)
                    .font(ScholiumTypography.interface(.body, emphasis: .strong))
                Spacer()
                Text(change.createdAt, style: .relative)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }

            Text(change.finalRelativePath ?? change.originalRelativePath ?? change.noteID.uuidString)
                .font(ScholiumTypography.scholarly(.body))
                .textSelection(.enabled)

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(stateTitle)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(change.state == .outcomeUncertain ? .attention : .secondaryText)
                Text(change.noteID.uuidString.lowercased())
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
                    .textSelection(.enabled)
                Spacer()
                if change.isDirectUndoEligible {
                    Button(isUndoing ? "Undoing…" : "Undo") {
                        Task { await undo() }
                    }
                    .disabled(isUndoing)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(
                        "scholium.agentChanges.undo.\(change.id.uuidString.lowercased())"
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var operationTitle: String {
        switch change.operation {
        case .create: "Created"
        case .update: "Updated"
        case .trash: "Moved to Trash"
        }
    }

    private var operationSymbol: String {
        switch change.operation {
        case .create: "doc.badge.plus"
        case .update: "pencil"
        case .trash: "trash"
        }
    }

    private var stateTitle: String {
        switch change.state {
        case .prepared: "Prepared"
        case .confirmed: "Confirmed"
        case .outcomeUncertain: "Outcome uncertain — inspect before retrying"
        case .undone: "Undone"
        }
    }
}
