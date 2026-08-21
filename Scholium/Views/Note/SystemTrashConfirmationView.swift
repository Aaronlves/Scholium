import ScholiumContracts
import SwiftUI

struct SystemTrashConfirmationView: View {
    let preview: SystemTrashDeletionPreview
    let confirm: (SystemTrashDeletionPreview) async throws -> Void
    let cancel: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Label("Move to macOS Trash?", systemImage: "trash")
                .font(ScholiumTypography.interface(.primaryTitle, emphasis: .strong))
                .accessibilityAddTraits(.isHeader)

            Text("Finder owns file restoration, but it cannot restore the finished Research Records that Scholium deletes after the file move succeeds.")
                .font(ScholiumTypography.interface(.body))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    GroupBox("Files and Folders") {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumGrid.Spacing.inlineControlGap
                        ) {
                            ForEach(preview.sources) { source in
                                Label(
                                    source.relativePath,
                                    systemImage: source.kind == .folder ? "folder" : "doc.text"
                                )
                                .lineLimit(2)
                                .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Application State Deleted Afterward") {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumGrid.Spacing.inlineControlGap
                        ) {
                            Text("\(preview.records.count) finished Research Record(s)")
                            ForEach(preview.records) { record in
                                VStack(
                                    alignment: .leading,
                                    spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                                ) {
                                    Text(record.title)
                                        .font(ScholiumTypography.interface(.body, emphasis: .medium))
                                    if !record.unaffectedParticipants.isEmpty {
                                        Text("This whole multi-Note Record will be deleted; these participating Notes are not being moved:")
                                            .font(ScholiumTypography.interface(.small))
                                            .scholiumForeground(.secondaryText)
                                        ForEach(record.unaffectedParticipants) { participant in
                                            Text("\(participant.title) — \(participant.relativePath)")
                                                .font(ScholiumTypography.interface(.small))
                                                .scholiumForeground(.secondaryText)
                                                .lineLimit(2)
                                                .truncationMode(.middle)
                                        }
                                    }
                                }
                            }
                            if !preview.activeDiscussionIDs.isEmpty {
                                Text("\(preview.activeDiscussionIDs.count) active Discussion(s) will be discarded without becoming Records.")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("These steps are recoverable separately, not atomically. If Record cleanup fails after Finder accepts the files, Scholium keeps a recovery plan and resumes only that confirmed cleanup. External file deletion never triggers this cascade.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxHeight: ScholiumMetrics.ResearchSheet.SystemTrash
                    .consequenceScrollMaximumHeight
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.destructive)
                    .accessibilityIdentifier("scholium.systemTrashError")
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Move to Trash and Delete Records", role: .destructive) {
                    perform()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.SystemTrash.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.SystemTrash.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.SystemTrash.minimumHeight
        )
        .overlay {
            if isWorking {
                ProgressView("Moving exact sources and applying the confirmed Record cleanup…")
                    .padding()
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.loadingSurfaceCornerRadius
                        )
                    )
            }
        }
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("scholium.systemTrashConfirmation")
    }

    private func perform() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await confirm(preview)
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
