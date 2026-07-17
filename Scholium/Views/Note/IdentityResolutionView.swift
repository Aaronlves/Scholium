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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Note Identity")
                        .font(.title2.weight(.semibold))
                    Text("Scholium found the file at a new location but cannot safely determine which previous note it belongs to.")
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Vault", value: vaultName)
            LabeledContent("Current Location") {
                Text(ambiguity.relativePath)
                    .textSelection(.enabled)
            }
            LabeledContent("Content Fingerprint") {
                Text(shortFingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .help(ambiguity.fingerprint.sha256)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Which note is this?")
                    .font(.headline)
                Picker("Note identity", selection: $choice) {
                    ForEach(ambiguity.candidates) { candidate in
                        Text("Previously at \(candidate.relativePath)")
                            .tag(Optional(Choice.existing(candidate.id)))
                            .accessibilityLabel("Use the note identity previously at \(candidate.relativePath)")
                    }
                    Text("This is a new note")
                        .tag(Optional(Choice.newNote))
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose one previous location, or identify the file as a new note.")
            }

            Text("Confirming a previous note moves its comments, Human Review, Dialogue references, Critique association, Note History, and window state to the current location. Scholium does not change the Markdown file.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Identity recovery failed. \(errorMessage)")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
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
                .keyboardShortcut(.defaultAction)
                .disabled(choice == nil || isResolving)
            }
        }
        .padding(24)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Identity Recovery Required")
                    .font(.headline)
                Text("This note remains readable, but Review, comments, History restore, and file changes are unavailable until its records finish moving from \(rebinding.previousRelativePath) to \(rebinding.relativePath).")
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            Button("Retry Identity Recovery") {
                Task { await onRetry() }
            }
            .disabled(isRetrying)
            .accessibilityHint("Retries migration of app-owned records without changing the Markdown note.")
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.35))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Persistent, nonmodal notice for a readable note whose stable identity needs
/// an explicit researcher choice.
struct IdentityAmbiguityNotice: View {
    let ambiguity: NoteIdentityAmbiguity
    let onResolve: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.folder")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Confirm Note Identity")
                    .font(.headline)
                Text(ambiguityExplanation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Choose Identity…", action: onResolve)
                .accessibilityHint("Shows the previous note locations without changing the Markdown file.")
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.35))
        }
        .accessibilityElement(children: .contain)
    }

    private var ambiguityExplanation: String {
        let opening = ambiguity.candidates.isEmpty
            ? "This file’s prior identity is unresolved."
            : "This file matches \(ambiguity.candidates.count) previous notes."
        return opening + " You can keep reading, but Review, comments, History restore, and file changes remain unavailable until you identify it."
    }
}
