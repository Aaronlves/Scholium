import ScholiumContracts
import SwiftUI

/// One document-local doorway for comments, role-appropriate review or
/// critique, and Dialogue. The records remain separate; this view only
/// provides a focused navigation surface.
struct ScholiaPanelContext {
    let vaultRole: VaultRole
    let humanReviewRecord: HumanReviewRecord?
    let canComment: Bool
    let canHumanReview: Bool
    let canEdit: Bool
    let hasResolvedIdentity: Bool
    let availableWindowWidth: CGFloat
    let openComments: () -> Void
    let prepareDialogue: () -> Void
}

struct ScholiaPanelView<Destination: View>: View {
    @ObservedObject private var controller: ResearchController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let note: WindowDocumentLocation
    let context: ScholiaPanelContext
    private let destinationContent: (ScholiaDestination) -> Destination

    init(
        note: WindowDocumentLocation,
        controller: ResearchController,
        context: ScholiaPanelContext,
        @ViewBuilder destination: @escaping (ScholiaDestination) -> Destination
    ) {
        self.note = note
        self.controller = controller
        self.context = context
        self.destinationContent = destination
    }

    private var commentsSectionTitle: String {
        context.vaultRole.allowsCritique
            ? "Comments & Critique"
            : "Comments & Review"
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            VStack(spacing: 0) {
                panelHeader

                Divider()

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if controller.scholia.section == .comments {
                            commentsAndReviewContent
                                .transition(sectionTransition)
                        } else {
                            dialogueContent
                                .transition(sectionTransition)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.18),
                    value: controller.scholia.section
                )
            }
            .accessibilityIdentifier("scholium.scholiaPanel")
            .navigationDestination(for: ScholiaDestination.self) { route in
                destination(for: route)
            }
        }
        // Every Scholia destination keeps its persistent footer reachable.
        // Dialogue's two-column note/instruction workflow is the widest child,
        // so the navigation container—not an overflowing destination—owns the
        // sheet's release-size contract.
        .frame(width: panelWidth)
        .frame(minHeight: 560, idealHeight: 700)
    }

    private var panelHeader: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scholia")
                        .font(ScholiumInterfaceTypography.sectionTitle)
                    Text(note.title ?? note.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Scholia section", selection: sectionBinding) {
                Text(commentsSectionTitle).tag(ScholiaSection.comments)
                Text("Dialogue").tag(ScholiaSection.dialogue)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 320)
            .accessibilityLabel("Scholia")
            .accessibilityIdentifier("scholium.scholiaSections")

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var panelWidth: CGFloat {
        let availableWidth = context.availableWindowWidth > 0
            ? context.availableWindowWidth
            : 1_012
        return min(940, max(520, availableWidth - 72))
    }

    private var sectionTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.992, anchor: .top))
    }

    @ViewBuilder
    private func destination(for route: ScholiaDestination) -> some View {
        destinationContent(route)
    }

    private var sectionBinding: Binding<ScholiaSection> {
        Binding(
            get: { controller.scholia.section },
            set: { section in
                if reduceMotion {
                    controller.selectScholiaSection(section)
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        controller.selectScholiaSection(section)
                    }
                }
            }
        )
    }

    private var navigationPath: Binding<[ScholiaDestination]> {
        Binding(
            get: { controller.scholia.path },
            set: { controller.replaceScholiaPath($0) }
        )
    }

    private var commentsAndReviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Comments")
                    .font(ScholiumInterfaceTypography.sectionTitle)
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
                                .font(ScholiumInterfaceTypography.overline)
                                .foregroundStyle(.secondary)
                            Text(comment.text)
                                .font(.callout)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if context.canComment {
                Button {
                    context.openComments()
                    controller.pushScholiaDestination(.comments)
                } label: {
                    Label("Add Comment…", systemImage: "plus.bubble")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("scholium.scholiaComments")
            }

            Divider()

            Text(context.vaultRole.allowsCritique ? "Critique" : "Human Review")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            if context.canHumanReview {
                Button {
                    controller.pushScholiaDestination(.review)
                } label: {
                    Label(reviewActionTitle, systemImage: "checkmark.seal")
                }
                .buttonStyle(.glassProminent)
                .disabled(!context.canHumanReview)
                .accessibilityIdentifier("scholium.scholiaReview")
            }

            if context.vaultRole.allowsCritique,
               !CritiquePlacement.isManagedCritiquePath(note.relativePath),
               context.canEdit {
                Button {
                    controller.pushScholiaDestination(.critique)
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
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Prepare this note and its comments for an external agent. Scholium copies instructions; it does not send research automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                context.prepareDialogue()
                controller.pushScholiaDestination(.dialogue)
            } label: {
                Label("Prepare Dialogue…", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(.glassProminent)
            .disabled(!context.hasResolvedIdentity)
            .accessibilityIdentifier("scholium.scholiaDialogue")
        }
    }

    private var reviewActionTitle: String {
        context.humanReviewRecord?.draft == nil
            ? "Open Human Review"
            : "Continue Human Review"
    }

    private var existingComments: [ResearcherComment] {
        context.humanReviewRecord?.comments ?? []
    }
}
