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

            Text("Finder owns file restoration. Scholium will remove only the listed sources and their portable identity and Critique associations.")
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

                    Text("If portable cleanup fails after Finder accepts the items, Scholium keeps a recovery plan. External file deletion only refreshes the workspace.")
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
                    .scholiumActivationPointer()
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Move to Trash", role: .destructive) {
                    perform()
                }
                .scholiumActivationPointer()
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
                ProgressView()
                    .accessibilityLabel("Moving items to Trash…")
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
