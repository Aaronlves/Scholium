import ScholiumContracts
import SwiftUI

/// Researcher confirmation for an external rename that cannot be rebound
/// without choosing among several stable identities.
struct IdentityResolutionView: View {
    private enum Choice: Hashable {
        case existing(UUID)
        case newNote
    }

    let ambiguity: NoteIdentityAmbiguity
    let vaultName: String
    let isResolving: Bool
    let errorMessage: String?
    let onConfirm: (UUID?) async -> Void
    let onCancel: () -> Void

    @State private var choice: Choice?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.sectionSpacing) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                Image(systemName: "questionmark.folder")
                    .scholiumSymbolStyle(.large)
                    .scholiumForeground(.attention)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("Confirm Note Identity")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    Text("Scholium found the file at a new location but cannot safely determine which previous note it belongs to.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                }
            }

            LabeledContent("Vault", value: vaultName)
            LabeledContent("Current Location") {
                Text(ambiguity.relativePath)
                    .font(ScholiumTypography.exact(.body))
                    .textSelection(.enabled)
            }
            LabeledContent("Content Fingerprint") {
                Text(shortFingerprint)
                    .font(ScholiumTypography.exact(.small))
                    .textSelection(.enabled)
                    .help(ambiguity.fingerprint.sha256)
            }

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Which note is this?")
                    .font(ScholiumTypography.interface(.sectionTitle))
                Picker("Note identity", selection: $choice) {
                    ForEach(ambiguity.candidates) { candidate in
                        Text("Previously at \(candidate.relativePath)")
                            .tag(Optional(Choice.existing(candidate.id)))
                            .accessibilityLabel("Use the note identity previously at \(candidate.relativePath)")
                    }
                    Text("This is a new note")
                        .tag(Optional(Choice.newNote))
                }
                .scholiumActivationPointer()
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose one previous location, or identify the file as a new note.")
            }

            Text("Confirming a previous note moves its portable identity, Critique association, and window state to the current location. Scholium does not change the Markdown file.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .scholiumForeground(.destructive)
                    .accessibilityLabel("Identity recovery failed. \(errorMessage)")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .scholiumActivationPointer()
                    .keyboardShortcut(.cancelAction)
                Button("Confirm Identity") {
                    let candidateID: UUID?
                    switch choice {
                    case .existing(let id): candidateID = id
                    case .newNote: candidateID = nil
                    case nil: return
                    }
                    Task { await onConfirm(candidateID) }
                }
                .scholiumActivationPointer()
                .keyboardShortcut(.defaultAction)
                .disabled(choice == nil || isResolving)
            }
        }
        .padding(ScholiumMetrics.DocumentWorkflow.identityContentInset)
        .frame(minWidth: 520, idealWidth: 580, maxWidth: 660)
        .disabled(isResolving)
        .overlay {
            if isResolving {
                ProgressView("Migrating app-owned records…")
                    .padding()
                    .scholiumEditorialSurface(
                        .floatingControl,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.loadingSurfaceCornerRadius,
                            style: .continuous
                        )
                    )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var shortFingerprint: String {
        String(ambiguity.fingerprint.sha256.prefix(12)) + "…"
    }
}

/// Persistent, document-local recovery state for an interrupted app-owned path
/// migration. It has no dismiss action because identity-dependent operations
/// remain blocked until retry succeeds.
struct IdentityMigrationNotice: View {
    let rebinding: NoteIdentityPendingRebinding
    let message: String?
    let isRetrying: Bool
    let onRetry: () async -> Void

    var body: some View {
        ScholiumRecoveryNotice(
            ScholiumRecoveryNoticePresentation(
                "Identity Recovery Required",
                message: Text("This note remains readable, but identity-dependent restore and file changes are unavailable until its portable records finish moving from \(rebinding.previousRelativePath) to \(rebinding.relativePath)."),
                detail: message.map { Text(verbatim: $0) },
                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
            ),
            region: .documentInline
        ) {
            Button("Retry Identity Recovery") {
                Task { await onRetry() }
            }
            .scholiumActivationPointer()
            .disabled(isRetrying)
            .accessibilityHint("Retries migration of app-owned records without changing the Markdown note.")
        }
    }
}

/// Persistent, nonmodal notice for a readable note whose stable identity needs
/// an explicit researcher choice.
struct IdentityAmbiguityNotice: View {
    let ambiguity: NoteIdentityAmbiguity
    let onResolve: () -> Void

    var body: some View {
        ScholiumRecoveryNotice(
            ScholiumRecoveryNoticePresentation(
                "Confirm Note Identity",
                message: Text(verbatim: ambiguityExplanation),
                systemImage: "questionmark.folder"
            ),
            region: .documentInline
        ) {
            Button("Choose Identity…", action: onResolve)
                .scholiumActivationPointer()
                .accessibilityHint("Shows the previous note locations without changing the Markdown file.")
        }
    }

    private var ambiguityExplanation: String {
        let opening = ambiguity.candidates.isEmpty
            ? "This file’s prior identity is unresolved."
            : "This file matches \(ambiguity.candidates.count) previous notes."
        return opening + " You can keep reading, but identity-dependent restore and file changes remain unavailable until you identify it."
    }
}
