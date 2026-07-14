import SwiftUI
import ScholiumCore

/// One document-local doorway for comments, role-appropriate review or
/// critique, and Dialogue. The records remain separate; this view only
/// provides a focused navigation surface.
struct ScholiaPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var path: [ScholiaRoute] = []

    private enum ScholiaRoute: Hashable {
        case comments
        case review
        case critique
        case dialogue
    }

    private var commentsSectionTitle: String {
        appState.currentVaultRole.allowsCritique
            ? "Comments & Critique"
            : "Comments & Review"
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scholia")
                            .font(.title2.weight(.semibold))
                        Text(note.title ?? note.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.glass)
                }
                .padding(18)

                Divider()

                Picker("Scholia section", selection: sectionBinding) {
                    Text(commentsSectionTitle).tag(AppState.ScholiaSection.comments)
                    Text("Dialogue").tag(AppState.ScholiaSection.dialogue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .accessibilityIdentifier("scholium.scholiaSections")

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if appState.scholiaSection == .comments {
                            commentsAndReviewContent
                        } else {
                            dialogueContent
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityIdentifier("scholium.scholiaPanel")
            .navigationDestination(for: ScholiaRoute.self) { route in
                destination(for: route)
            }
        }
        // Every Scholia destination keeps its persistent footer reachable.
        // Dialogue's two-column note/instruction workflow is the widest child,
        // so the navigation container—not an overflowing destination—owns the
        // sheet's release-size contract.
        .frame(minWidth: 820, idealWidth: 940, minHeight: 600, idealHeight: 700)
    }

    @ViewBuilder
    private func destination(for route: ScholiaRoute) -> some View {
        switch route {
        case .comments:
            ResearcherCommentsView(note: note)
                .environmentObject(appState)
        case .review:
            QualityReviewView(note: note)
                .environmentObject(appState)
        case .critique:
            CritiqueRequestView(note: note)
                .environmentObject(appState)
        case .dialogue:
            DialogueView()
                .environmentObject(appState)
        }
    }

    private var sectionBinding: Binding<AppState.ScholiaSection> {
        Binding(
            get: { appState.scholiaSection },
            set: { appState.scholiaSection = $0 }
        )
    }

    private var commentsAndReviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Comments")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(existingComments.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if existingComments.isEmpty {
                Text("No researcher comments for this note.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(existingComments.prefix(3)) { comment in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.anchor == nil ? "Whole note" : "Selection comment")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(comment.text)
                                .font(.callout)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if appState.canCommentCurrentNote {
                Button {
                    appState.researcherCommentsPath = note.relativePath
                    path.append(.comments)
                } label: {
                    Label("Add Comment…", systemImage: "plus.bubble")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("scholium.scholiaComments")
            }

            Divider()

            Text(appState.currentVaultRole.allowsCritique ? "Critique" : "Human Review")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if appState.canHumanReviewCurrentNote {
                Button {
                    path.append(.review)
                } label: {
                    Label(reviewActionTitle, systemImage: "checkmark.seal")
                }
                .buttonStyle(.glassProminent)
                .disabled(!appState.canHumanReviewCurrentNote)
                .accessibilityIdentifier("scholium.scholiaReview")
            }

            if appState.currentVaultRole.allowsCritique,
               !CritiquePlacement.isManagedCritiquePath(note.relativePath),
               appState.canEditCurrentNote {
                Button {
                    path.append(.critique)
                } label: {
                    Label("Request Critique…", systemImage: "sparkles")
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("scholium.scholiaCritique")
            }
        }
    }

    private var dialogueContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dialogue")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Prepare this note and its comments for an external agent. Scholium copies instructions; it does not send research automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                if let vaultID = appState.currentRegisteredVault?.id,
                   let noteID = appState.noteIdentityByPath[note.relativePath] {
                    appState.dialogueInitialNotes = [VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: note.relativePath
                    )]
                    _ = noteID
                }
                path.append(.dialogue)
            } label: {
                Label("Prepare Dialogue…", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(.glassProminent)
            .disabled(appState.noteIdentityByPath[note.relativePath] == nil)
            .accessibilityIdentifier("scholium.scholiaDialogue")
        }
    }

    private var reviewActionTitle: String {
        appState.humanReviewRecord(for: note.relativePath)?.draft == nil
            ? "Open Human Review"
            : "Continue Human Review"
    }

    private var existingComments: [ResearcherComment] {
        appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
    }
}
