import ScholiumContracts
import SwiftUI

@MainActor
struct ExternalMarkdownImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var bootstrap: ApplicationBootstrapController
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @ObservedObject var original: ExternalMarkdownWindowModel
    @State private var assignments: [TriptychAssignment] = []
    @State private var triptychID: UUID?
    @State private var slot: WorkspaceVaultSlot?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var error: String?
    @State private var imported: VaultNoteReference?

    private var store: WorkspaceStore? {
        if case .ready(let store) = bootstrap.state { return store }
        return nil
    }

    var body: some View {
        FileOperationSheet(
            title: Text("Import to Triptych…"),
            message: Text("Import a copy of the current content. The original file stays in place.")
        ) {
            Text(original.title).textSelection(.enabled)
            if isLoading {
                ProgressView("Loading Triptychs…")
            } else if assignments.isEmpty {
                Text("No Triptych Available")
                Button("New Triptych…") {
                    openWindow(id: "scholium-bootstrap", value: BootstrapWindowRoute(purpose: .newTriptych))
                    dismiss()
                }
            } else {
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    Picker("Triptych", selection: $triptychID) {
                        Text("Choose Triptych").tag(UUID?.none)
                        ForEach(assignments) { assignment in
                            Text(assignment.triptych.name).tag(Optional(assignment.id))
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("scholium.externalMarkdown.import.triptych")
                    Picker("Workspace", selection: $slot) {
                        Text("Choose Workspace").tag(WorkspaceVaultSlot?.none)
                        ForEach(WorkspaceVaultSlot.allCases) { slot in
                            Text(ScholiumL10n.dynamicString(slot.displayName)).tag(Optional(slot))
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("scholium.externalMarkdown.import.workspace")
                    if let selected = assignments.first(where: { $0.id == triptychID }), let slot,
                        let vault = selected.vault(for: slot)
                    {
                        Text(vault.canonicalPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.disabled(isWorking || imported != nil)
            }
            if let error { Text(error).textSelection(.enabled).accessibilityIdentifier("scholium.externalMarkdown.import.error") }
            if let imported {
                if original.pendingImport?.requiresRecovery == true {
                    Text("Import needs recovery: \(imported.relativePath)").textSelection(.enabled)
                } else {
                    Text("Imported: \(imported.relativePath)").textSelection(.enabled)
                }
            }
        } actions: {
            if isWorking { ProgressView().controlSize(.small) }
            Spacer()
            Button {
                dismiss()
            } label: {
                if imported == nil { Text("Cancel") } else { Text("Done") }
            }
            .keyboardShortcut(.cancelAction).disabled(isWorking)
            if let imported, let triptychID {
                Button {
                    Task { await reveal(imported, triptychID: triptychID) }
                } label: {
                    if original.pendingImport?.requiresRecovery == true { Text("Open Recovery") } else { Text("Open Imported Note") }
                }.disabled(isWorking)
            } else if assignments.isEmpty {
                Button("Retry") { Task { await load() } }.disabled(isLoading || isWorking)
            } else {
                Button("Import") { Task { await performImport() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || !original.canImport || triptychID == nil || slot == nil)
                    .accessibilityIdentifier("scholium.externalMarkdown.import.confirm")
            }
        }
        .interactiveDismissDisabled(isWorking)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let recovery = original.pendingImport {
            imported = recovery.reference
            triptychID = recovery.triptychID
            error = recovery.message
        }
        guard let store else {
            error = ScholiumL10n.string("Triptych storage is unavailable. The original file remains open.")
            return
        }
        do {
            if let pending = original.pendingImport, let record = pending.recoveryRecord {
                if try await store.externalMarkdownRecoveryIsPending(record) {
                    // This read now proves persistence even if the original
                    // attempt could not prove it. Reconciliation owns removal.
                    original.pendingImport?.persistenceFailure = nil
                } else if pending.persistenceFailure == nil {
                    original.pendingImport = nil
                    imported = nil
                }
            }
            assignments = try await store.registeredTriptychs()
            if assignments.count == 1, triptychID == nil { triptychID = assignments.first?.id }
            if original.pendingImport == nil { error = nil }
        } catch { self.error = ScholiumErrorLocalization.message(error) }
    }

    private func performImport() async {
        guard !isWorking, imported == nil, let store, let triptychID, let slot,
            let assignment = assignments.first(where: { $0.id == triptychID })
        else { return }
        isWorking = true
        error = nil
        defer {
            original.importCommitInProgress = false
            isWorking = false
        }
        do {
            let bytes = try await original.captureImport()
            original.importCommitInProgress = true
            let (reference, outcome) = try await store.importExternalMarkdown(
                bytes, filename: original.title, assignment: assignment, slot: slot)
            // Keep the committed identity before attempting presentation. Retry
            // opens this copy and never issues another import transaction.
            imported = reference
            let warnings = [outcome.derivedRefreshWarning, outcome.identityRecoveryWarning].compactMap { $0 }
            original.pendingImport = ExternalMarkdownImportResult(
                reference: reference, triptychID: triptychID,
                message: warnings.isEmpty ? nil : warnings.joined(separator: "\n"), requiresRecovery: false)
            if !warnings.isEmpty {
                error = warnings.joined(separator: "\n")
                return
            }
            try await applicationDelegate.markdownFiles.openImported(reference, in: triptychID)
            if original.pendingImport?.requiresRecovery != true { original.pendingImport = nil }
            dismiss()
        } catch {
            self.error = ScholiumErrorLocalization.message(error)
            original.pendingImport?.message = self.error
            if let transaction = error as? TriptychTransactionError {
                let record: TriptychMutationRecoveryRecord?
                let persistenceFailure: String?
                switch transaction {
                case .recoveryRequired(let recovery):
                    record = recovery
                    persistenceFailure = nil
                case .recoveryPersistenceFailed(let recovery, let detail):
                    record = recovery
                    persistenceFailure = detail
                default:
                    record = nil
                    persistenceFailure = nil
                }
                if let target = record?.managedCreation?.target,
                    let vault = assignment.vaults.values.first(where: { $0.id == target.vaultID })
                {
                    let reference = VaultNoteReference(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, relativePath: target.relativePath)
                    imported = reference
                    original.pendingImport = ExternalMarkdownImportResult(
                        reference: reference, triptychID: triptychID, message: self.error, requiresRecovery: true,
                        recoveryRecord: record, persistenceFailure: persistenceFailure)
                }
            }
        }
    }

    private func reveal(_ reference: VaultNoteReference, triptychID: UUID) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if let recovery = original.pendingImport?.recoveryRecord {
                try await applicationDelegate.markdownFiles.openRecovery(recovery, persistenceFailure: original.pendingImport?.persistenceFailure)
            } else {
                try await applicationDelegate.markdownFiles.openImported(reference, in: triptychID)
            }
            if original.pendingImport?.requiresRecovery != true { original.pendingImport = nil }
            dismiss()
        } catch { self.error = ScholiumErrorLocalization.message(error) }
    }
}
