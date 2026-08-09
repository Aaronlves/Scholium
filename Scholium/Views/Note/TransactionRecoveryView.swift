import ScholiumContracts
import AppKit
import SwiftUI

/// Persistent, nonmodal indication that a multi-file move or classification
/// could not be completely rolled back. It remains visible until the
/// researcher explicitly marks each durable recovery record complete.
struct TransactionRecoveryNotice: View {
    let count: Int
    let error: String?
    let onInspect: () -> Void

    var body: some View {
        ScholiumRecoveryNotice(
            presentation,
            region: .workspaceBanner
        ) {
            Button("Inspect Recovery…", action: onInspect)
        }
        .accessibilityIdentifier("scholium.transactionRecovery.notice")
    }

    private var presentation: ScholiumRecoveryNoticePresentation {
        if let error {
            ScholiumRecoveryNoticePresentation(
                "Recovery Records Unavailable",
                message: Text(verbatim: error),
                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
            )
        } else {
            ScholiumRecoveryNoticePresentation(
                "Transaction Recovery Required",
                message: Text(verbatim: "\(count) interrupted operation\(count == 1 ? "" : "s") need file-by-file inspection."),
                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
            )
        }
    }
}

struct TransactionRecoveryView: View {
    @Environment(\.dismiss) private var dismiss

    let records: [TriptychMutationRecoveryRecord]
    let error: String?
    let interruptedSaves: [InterruptedSaveRecovery]
    let interruptedSaveError: String?
    let vaultNames: [UUID: String]
    let refresh: @MainActor () async -> Void
    let markResolved: @MainActor (UUID) async throws -> Void
    let revealRecords: @MainActor () -> Void
    let loadInterruptedSave: @MainActor (InterruptedSaveRecovery) async throws
        -> InterruptedSaveRecoveryContent
    let revealInterruptedSave: @MainActor (InterruptedSaveRecovery) async throws -> Void
    let restoreInterruptedSave: @MainActor (InterruptedSaveRecovery) async throws
        -> InterruptedSaveRecoveryRestoreCommit

    @State private var selectedRecord: TriptychMutationRecoveryRecord?
    @State private var selectedInterruptedSave: InterruptedSaveRecovery?
    @State private var operationError: String?
    @State private var completionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if records.isEmpty,
               interruptedSaves.isEmpty,
               error == nil,
               interruptedSaveError == nil {
                ScholiumContentStateView(
                    "No Pending Recovery",
                    detail: Text("No interrupted save candidate or recorded file operation needs inspection."),
                    indicator: .symbol("checkmark.circle")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let interruptedSaveError {
                        recoveryErrorSection(
                            title: "Interrupted Saves Unavailable",
                            message: interruptedSaveError
                        )
                    }
                    if !interruptedSaves.isEmpty {
                        Section("INTERRUPTED SAVES") {
                            ForEach(interruptedSaves) { recovery in
                                InterruptedSaveRecoveryRow(
                                    recovery: recovery,
                                    vaultName: vaultName(recovery.id.vaultID),
                                    loadContent: { try await loadInterruptedSave(recovery) },
                                    reveal: { try await revealInterruptedSave(recovery) },
                                    requestRestore: { selectedInterruptedSave = recovery }
                                )
                            }
                        }
                    }
                    if let error {
                        recoveryErrorSection(
                            title: "Operation Records Unavailable",
                            message: error
                        )
                    }
                    ForEach(records) { record in
                        recoverySection(record)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 0, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .task { await refresh() }
        .alert("Mark Recovery Complete?", isPresented: Binding(
            get: { selectedRecord != nil },
            set: { if !$0 { selectedRecord = nil } }
        )) {
            Button("Cancel", role: .cancel) { selectedRecord = nil }
            Button("Mark Recovery Complete") {
                guard let record = selectedRecord else { return }
                selectedRecord = nil
                Task {
                    do {
                        try await markResolved(record.id)
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Use this only after you have inspected every listed path and completed any checkpoint or Finder recovery. This removes the recovery record; it does not change research files.")
        }
        .alert("Restore Interrupted Save?", isPresented: Binding(
            get: { selectedInterruptedSave != nil },
            set: { if !$0 { selectedInterruptedSave = nil } }
        )) {
            Button("Cancel", role: .cancel) { selectedInterruptedSave = nil }
            Button(interruptedSaveConfirmationButtonTitle) {
                guard let recovery = selectedInterruptedSave else { return }
                selectedInterruptedSave = nil
                operationError = nil
                completionMessage = nil
                Task { @MainActor in
                    do {
                        let commit = try await restoreInterruptedSave(recovery)
                        completionMessage = commit.didReplaceSource
                            ? String(
                                localized: "The interrupted candidate is now the current source.",
                                table: "Localizable",
                                bundle: .module
                            )
                            : String(
                                localized: "The candidate already matched the current source; its recovery record was completed.",
                                table: "Localizable",
                                bundle: .module
                            )
                    } catch {
                        operationError = error.localizedDescription
                        await refresh()
                    }
                }
            }
        } message: {
            Text(interruptedSaveConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .scholiumSymbolStyle(.large)
                .scholiumForeground(.attention)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Recovery")
                    .font(ScholiumTypography.interface(.primaryTitle))
                Text("Inspect exact save candidates retained after an interruption and durable records from file operations that could not finish cleanly.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
    }

    @ViewBuilder
    private func recoverySection(_ record: TriptychMutationRecoveryRecord) -> some View {
        Section {
            LabeledContent("Operation", value: operationName(record.operation))
            LabeledContent("Recorded", value: record.createdAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent("Failure") {
                Text(record.failure)
                    .font(ScholiumTypography.interface(.body))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
            ForEach(record.files) { file in
                RecoveryFileRow(file: file, vaultName: vaultName(file.vaultID))
            }
            HStack {
                Spacer()
                Button("Mark Recovery Complete…") { selectedRecord = record }
            }
        } header: {
            Text(operationName(record.operation))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if let operationError {
                Label("Recovery could not be completed. \(operationError)", systemImage: "exclamationmark.triangle.fill")
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
            }
            if let completionMessage {
                Label(completionMessage, systemImage: "checkmark.circle")
                    .scholiumForeground(.confirmed)
            }
            HStack {
                if !records.isEmpty || error != nil {
                    Button("Reveal Operation Records in Finder") {
                        revealRecords()
                    }
                }
                Button("Refresh") {
                    Task { await refresh() }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
    }

    private func recoveryErrorSection(
        title: LocalizedStringKey,
        message: String
    ) -> some View {
        Section(title) {
            Label {
                Text(message)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .scholiumForeground(.attention)
        }
    }

    private var interruptedSaveConfirmationButtonTitle: String {
        guard selectedInterruptedSave?.sourceState == .candidateRevision else {
            return String(
                localized: "Restore Candidate",
                table: "Localizable",
                bundle: .module
            )
        }
        return String(
            localized: "Finish Recovery",
            table: "Localizable",
            bundle: .module
        )
    }

    private var interruptedSaveConfirmationMessage: String {
        guard selectedInterruptedSave?.sourceState == .candidateRevision else {
            return String(
                localized: "Scholium first saves every open editor, then restores only if this Note still has the expected revision. If the source changed, recovery stops and keeps the candidate.",
                table: "Localizable",
                bundle: .module
            )
        }
        return String(
            localized: "Scholium first saves every open editor, verifies that the candidate is still the canonical source, and then removes only its completed machine-local recovery record.",
            table: "Localizable",
            bundle: .module
        )
    }

    private func vaultName(_ vaultID: UUID?) -> String {
        guard let vaultID else { return "External file" }
        return vaultNames[vaultID] ?? "Vault \(vaultID.uuidString)"
    }

    private func operationName(_ operation: TriptychMutationOperation) -> String {
        switch operation {
        case .noteSave: "Save Note"
        case .noteMove: "Move or Rename Note"
        case .folderMove:
            String(
                localized: "Move or Rename Folder",
                table: "Localizable",
                bundle: .module
            )
        case .permanentDeletion: "Permanent Deletion"
        }
    }
}

private struct InterruptedSaveRecoveryRow: View {
    let recovery: InterruptedSaveRecovery
    let vaultName: String
    let loadContent: @MainActor () async throws -> InterruptedSaveRecoveryContent
    let reveal: @MainActor () async throws -> Void
    let requestRestore: @MainActor () -> Void

    @State private var isSourceExpanded = false
    @State private var content: InterruptedSaveRecoveryContent?
    @State private var isLoading = false
    @State private var contentError: String?
    @State private var actionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(sourceStateTitle, systemImage: sourceStateSymbol)
                    .font(ScholiumTypography.interface(.sectionTitle))
                Spacer()
                Text("Interrupted save")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Text(verbatim: vaultName)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Text(verbatim: recovery.relativePath)
                .font(ScholiumTypography.exact(.body))
                .textSelection(.enabled)
            Text("Expected: \(short(recovery.expectedRevision))")
                .font(ScholiumTypography.exact(.small))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
            Text("Candidate: \(short(recovery.candidateRevision))")
                .font(ScholiumTypography.exact(.small))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
            Text(recovery.retainedReason)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let sourceStateDetail {
                Text(sourceStateDetail)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            DisclosureGroup("View Candidate Source", isExpanded: $isSourceExpanded) {
                candidateSource
                    .task(id: isSourceExpanded) {
                        guard isSourceExpanded else { return }
                        await loadCandidateIfNeeded()
                    }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    revealButton
                    restoreButton
                    Spacer()
                    timestamp
                }
                VStack(alignment: .leading, spacing: 6) {
                    timestamp
                    revealButton
                    restoreButton
                }
            }
            if let actionMessage {
                Text(actionMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var candidateSource: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading candidate…")
        } else if let content {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if content.exactSource.isEmpty {
                    Text("This candidate is an empty document.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                } else {
                    ScrollView {
                        Text(verbatim: content.exactSource)
                            .font(ScholiumTypography.exact(.body))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                    .accessibilityLabel("Interrupted save candidate source")
                }
                Button("Copy Candidate") { copy(content.exactSource) }
            }
        } else if let contentError {
            Text(contentError)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
        }
    }

    @MainActor
    private func loadCandidateIfNeeded() async {
        guard content == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            content = try await loadContent()
            contentError = nil
        } catch {
            contentError = error.localizedDescription
        }
    }

    private func copy(_ exactSource: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exactSource, forType: .string)
        actionMessage = String(
            localized: "Candidate copied.",
            table: "Localizable",
            bundle: .module
        )
    }

    private var revealButton: some View {
        Button("Reveal Candidate in Finder") {
            Task { @MainActor in
                do {
                    try await reveal()
                    actionMessage = nil
                } catch {
                    actionMessage = error.localizedDescription
                }
            }
        }
    }

    private var restoreButton: some View {
        Button(restoreButtonTitle) { requestRestore() }
            .disabled(!recovery.sourceState.permitsRecovery)
            .help(restoreHelp)
    }

    private var timestamp: some View {
        Text(recovery.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(ScholiumTypography.interface(.small))
            .scholiumForeground(.mutedText)
    }

    private var sourceStateTitle: String {
        switch recovery.sourceState {
        case .expectedRevision:
            String(localized: "Candidate ready to restore", table: "Localizable", bundle: .module)
        case .candidateRevision:
            String(localized: "Candidate is already current", table: "Localizable", bundle: .module)
        case .changed:
            String(localized: "Current source changed", table: "Localizable", bundle: .module)
        case .missing:
            String(localized: "Current source is missing", table: "Localizable", bundle: .module)
        case .unavailable:
            String(localized: "Current source unavailable", table: "Localizable", bundle: .module)
        }
    }

    private var sourceStateSymbol: String {
        switch recovery.sourceState {
        case .expectedRevision:
            "arrow.uturn.backward.circle"
        case .candidateRevision:
            "checkmark.circle"
        case .changed:
            "exclamationmark.triangle"
        case .missing:
            "questionmark.folder"
        case .unavailable:
            "lock.trianglebadge.exclamationmark"
        }
    }

    private var sourceStateDetail: String? {
        switch recovery.sourceState {
        case .expectedRevision:
            nil
        case .candidateRevision:
            String(
                localized: "The candidate already matches the canonical source. Finishing recovery removes only the completed machine-local record.",
                table: "Localizable",
                bundle: .module
            )
        case .changed(let fingerprint):
            String(
                localized: "The current source is now \(short(fingerprint)). Scholium will not overwrite it; inspect or copy the retained candidate instead.",
                table: "Localizable",
                bundle: .module
            )
        case .missing:
            String(
                localized: "Scholium will not recreate a missing Note from temporary recovery. Inspect or copy the retained candidate instead.",
                table: "Localizable",
                bundle: .module
            )
        case .unavailable(let reason):
            String(
                localized: "Scholium could not verify the current Note and will not write it. \(reason)",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private var restoreButtonTitle: String {
        switch recovery.sourceState {
        case .candidateRevision:
            String(localized: "Finish Recovery…", table: "Localizable", bundle: .module)
        case .expectedRevision, .changed, .missing, .unavailable:
            String(localized: "Restore Candidate…", table: "Localizable", bundle: .module)
        }
    }

    private var restoreHelp: String {
        switch recovery.sourceState {
        case .expectedRevision:
            String(
                localized: "Restore only if the current Note still matches the expected revision",
                table: "Localizable",
                bundle: .module
            )
        case .candidateRevision:
            String(
                localized: "Verify the candidate is current and remove its completed recovery record",
                table: "Localizable",
                bundle: .module
            )
        case .changed:
            String(
                localized: "The current Note changed; copy or inspect the candidate instead",
                table: "Localizable",
                bundle: .module
            )
        case .missing:
            String(
                localized: "The current Note is missing; copy or inspect the candidate instead",
                table: "Localizable",
                bundle: .module
            )
        case .unavailable(let reason):
            String(
                localized: "The current Note cannot be verified: \(reason)",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        String(fingerprint.sha256.prefix(12)) + "… (\(fingerprint.byteCount) bytes)"
    }
}

private struct RecoveryFileRow: View {
    let file: TriptychMutationRecoveryFile
    let vaultName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(stateName, systemImage: stateSymbol)
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .scholiumForeground(stateColorRole)
                Spacer()
                Text(roleName)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Text(vaultName)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Text(file.path)
                .font(ScholiumTypography.exact(.body))
                .textSelection(.enabled)
            if let alternatePath = file.alternatePath {
                Text("Also inspect: \(alternatePath)")
                    .font(ScholiumTypography.exact(.body))
                    .textSelection(.enabled)
            }
            Text(file.detail)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
            if let observed = file.observedRevision {
                Text("Observed revision: \(short(observed))")
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stateName), \(roleName), \(vaultName), \(file.path)")
    }

    private var roleName: String {
        switch file.role {
        case .savedNote: "Saved note"
        case .movedNote: "Moved note"
        case .movedFolder:
            String(localized: "Moved folder", table: "Localizable", bundle: .module)
        case .incomingLinkRewrite: "Incoming link rewrite"
        case .deletedNote: "Deleted note"
        case .associatedCritique: "Associated Critique"
        }
    }

    private var stateName: String {
        switch file.state {
        case .restored: "Restored"
        case .intendedBytesRemain: "Intended changes remain"
        case .externallyChanged: "Externally changed"
        case .missing: "Missing"
        case .unreadable: "Unreadable"
        }
    }

    private var stateSymbol: String {
        switch file.state {
        case .restored: "checkmark.circle"
        case .intendedBytesRemain: "arrow.right.circle"
        case .externallyChanged: "exclamationmark.triangle"
        case .missing: "questionmark.folder"
        case .unreadable: "lock.trianglebadge.exclamationmark"
        }
    }

    private var stateColorRole: ScholiumColorRole {
        switch file.state {
        case .restored: .secondaryText
        case .intendedBytesRemain, .externallyChanged, .missing, .unreadable: .attention
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        String(fingerprint.sha256.prefix(12)) + "… (\(fingerprint.byteCount) bytes)"
    }
}
