import SwiftUI

/// One authorization repair for an already configured Triptych. It never
/// exposes Welcome, Triptych creation, or the other configured locations.
struct RestoreWorkspaceAccessView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter

    let recovery: WorkspaceAccessRecovery
    let restore: (URL) async throws -> Void
    let rebuildPortableControl: () async throws -> URL
    let archiveNoteMetadataRecord: () async throws -> URL
    let canRemoveRegistration: Bool
    let removeRegistration: () async throws -> Void
    let quitApplication: () -> Void

    @State private var isRestoring = false
    @State private var isRemovingRegistration = false
    @State private var isRebuildingPortableControl = false
    @State private var confirmsRegistrationRemoval = false
    @State private var confirmsPortableControlRebuild = false
    @State private var confirmsMetadataRecordArchive = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Text("Restore Access")
                .font(ScholiumTypography.interface(.primaryTitle))

            Text(explanation)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(recovery.expectedPath)
                .font(ScholiumTypography.exact(.body))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = recovery.reason {
                Text(reason)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canRemoveRegistration {
                Button("Remove Registration…", role: .destructive) {
                    confirmsRegistrationRemoval = true
                }
                .scholiumActivationPointer()
                .disabled(isBusy)
            }

            HStack {
                Button("Quit Scholium") { quitApplication() }
                    .scholiumActivationPointer()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(primaryTitle) {
                    if recovery.kind == .unsupportedPortableControl {
                        confirmsPortableControlRebuild = true
                    } else if recovery.kind == .invalidNoteMetadataRecord {
                        confirmsMetadataRecordArchive = true
                    } else {
                        chooseFolder()
                    }
                }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(width: 500)
        .interactiveDismissDisabled()
        .confirmationDialog(
            "Remove This Triptych Registration?",
            isPresented: $confirmsRegistrationRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Registration", role: .destructive) {
                removeTriptychRegistration()
            }
            .scholiumActivationPointer()
            Button("Cancel", role: .cancel) {}
            .scholiumActivationPointer()
        } message: {
            Text("Scholium will remove only this Triptych’s registration from this Mac, then open setup again. It will not delete or change Analyses, Topics, Works, or the portable .scholium folder.")
        }
        .confirmationDialog(
            "Archive and Rebuild Portable Control?",
            isPresented: $confirmsPortableControlRebuild,
            titleVisibility: .visible
        ) {
            Button("Archive and Rebuild", role: .destructive) {
                rebuildControl()
            }
            .scholiumActivationPointer()
            Button("Cancel", role: .cancel) {}
            .scholiumActivationPointer()
        } message: {
            Text("Scholium will move the entire existing .scholium folder to a uniquely named sibling recovery folder, preserving its exact files without interpreting the old schema. Analyses, Topics, and Works will not be changed. Scholium will then create current portable control state.")
        }
        .confirmationDialog(
            "Archive Invalid Metadata Record?",
            isPresented: $confirmsMetadataRecordArchive,
            titleVisibility: .visible
        ) {
            Button("Archive Record", role: .destructive) {
                archiveMetadataRecord()
            }
            .scholiumActivationPointer()
            Button("Cancel", role: .cancel) {}
            .scholiumActivationPointer()
        } message: {
            Text("Scholium will preserve this record’s exact bytes under a unique recovery name, remove only that invalid record from the active Metadata catalog, and reload the Triptych. Markdown and every other portable control file remain unchanged.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.restoreAccess")
    }

    private var explanation: String {
        switch recovery.kind {
        case .vault:
            String(
                localized: "Choose the same registered vault folder again so macOS can renew Scholium’s access. Other Triptych locations remain unchanged.",
                table: "Localizable",
                bundle: .module
            )
        case .portableControl:
            String(
                localized: "Choose the folder containing Works again so Scholium can renew access to the adjacent portable .scholium folder. Other Triptych locations remain unchanged.",
                table: "Localizable",
                bundle: .module
            )
        case .unsupportedPortableControl:
            String(
                localized: "This Triptych’s portable .scholium control folder is incompatible or damaged. Archive the entire folder unchanged, then let Scholium rebuild current control state. Analyses, Topics, and Works remain untouched.",
                table: "Localizable",
                bundle: .module
            )
        case .invalidNoteMetadataRecord:
            String(
                localized: "One portable Note Metadata record is damaged, orphaned, or incompatible with its current role. Archive only that exact record so Scholium can reload the remaining Metadata catalog.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private var primaryTitle: LocalizedStringResource {
        switch recovery.kind {
        case .unsupportedPortableControl: "Archive and Rebuild…"
        case .invalidNoteMetadataRecord: "Archive Record…"
        case .vault, .portableControl: "Choose Folder…"
        }
    }

    private var isBusy: Bool {
        isRestoring || isRemovingRegistration || isRebuildingPortableControl
    }

    private func archiveMetadataRecord() {
        isRebuildingPortableControl = true
        errorMessage = nil
        Task {
            do {
                _ = try await archiveNoteMetadataRecord()
            } catch {
                errorMessage = error.localizedDescription
            }
            isRebuildingPortableControl = false
        }
    }

    private func chooseFolder() {
        let expectedURL = URL(
            fileURLWithPath: recovery.expectedPath,
            isDirectory: true
        )
        let request = ScholiumFileSelectionRequest(
            prompt: String(
                localized: "Restore Access",
                table: "Localizable",
                bundle: .module
            ),
            initialDirectoryURL: expectedURL.deletingLastPathComponent(),
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expectedURL,
                rejectionMessage: String(
                    localized: "Choose the same registered folder shown above.",
                    table: "Localizable",
                    bundle: .module
                )
            )
        )
        Task { @MainActor in
            do {
                guard let url = try await fileSelectionPresenter
                    .requiredForFileSelection()
                    .selectURL(request) else { return }
                isRestoring = true
                errorMessage = nil
                try await restore(url)
                isRestoring = false
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }

    private func removeTriptychRegistration() {
        Task { @MainActor in
            do {
                isRemovingRegistration = true
                errorMessage = nil
                try await removeRegistration()
                isRemovingRegistration = false
            } catch is CancellationError {
                isRemovingRegistration = false
            } catch {
                errorMessage = error.localizedDescription
                isRemovingRegistration = false
            }
        }
    }

    private func rebuildControl() {
        Task { @MainActor in
            do {
                isRebuildingPortableControl = true
                errorMessage = nil
                _ = try await rebuildPortableControl()
                isRebuildingPortableControl = false
            } catch is CancellationError {
                isRebuildingPortableControl = false
            } catch {
                errorMessage = error.localizedDescription
                isRebuildingPortableControl = false
            }
        }
    }
}
