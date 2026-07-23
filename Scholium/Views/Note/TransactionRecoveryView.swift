import ScholiumContracts
import SwiftUI

/// Persistent, nonmodal indication that a multi-file move or classification
/// could not be completely rolled back. It remains visible until the
/// researcher explicitly marks each durable recovery record complete.
struct TransactionRecoveryNotice: View {
    let count: Int
    let error: String?
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(error == nil ? "Transaction Recovery Required" : "Recovery Records Unavailable")
                    .font(.headline)
                Text(error ?? "\(count) interrupted operation\(count == 1 ? "" : "s") need file-by-file inspection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button("Inspect Recovery…", action: onInspect)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.transactionRecovery.notice")
    }
}

struct TransactionRecoveryView: View {
    @Environment(\.dismiss) private var dismiss

    let records: [TriptychMutationRecoveryRecord]
    let error: String?
    let vaultNames: [UUID: String]
    let refresh: @MainActor () async -> Void
    let markResolved: @MainActor (UUID) async throws -> Void
    let revealRecords: @MainActor () -> Void

    @State private var selectedRecord: TriptychMutationRecoveryRecord?
    @State private var resolutionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error {
                ContentUnavailableView(
                    "Recovery Records Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView(
                    "No Pending Recovery",
                    systemImage: "checkmark.circle",
                    description: Text("Every recorded multi-file operation has been inspected.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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
                        resolutionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Use this only after you have inspected every listed path and completed any checkpoint or Finder recovery. This removes the recovery record; it does not change research files.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Transaction Recovery")
                    .font(.title2.weight(.semibold))
                Text("Scholium does not claim that a multi-file operation is atomic across vaults or filesystems. These durable records identify what was restored and what still needs inspection.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func recoverySection(_ record: TriptychMutationRecoveryRecord) -> some View {
        Section {
            LabeledContent("Operation", value: operationName(record.operation))
            LabeledContent("Recorded", value: record.createdAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent("Failure") {
                Text(record.failure)
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
        VStack(alignment: .leading, spacing: 8) {
            if let resolutionError {
                Label("Recovery record could not be updated. \(resolutionError)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Reveal Recovery Records in Finder") {
                    revealRecords()
                }
                if error != nil {
                    Button("Retry") {
                        Task { await refresh() }
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    private func vaultName(_ vaultID: UUID?) -> String {
        guard let vaultID else { return "Unclassified" }
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
        case .unclassifiedClassification: "Classify Imported Note"
        case .permanentDeletion: "Permanent Deletion"
        }
    }
}

private struct RecoveryFileRow: View {
    let file: TriptychMutationRecoveryFile
    let vaultName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(stateName, systemImage: stateSymbol)
                    .font(.headline)
                    .foregroundStyle(stateColor)
                Spacer()
                Text(roleName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(vaultName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(file.path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            if let alternatePath = file.alternatePath {
                Text("Also inspect: \(alternatePath)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text(file.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let observed = file.observedRevision {
                Text("Observed revision: \(short(observed))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
        case .classifiedSource: "Unclassified source"
        case .classifiedDestination: "Classified destination"
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

    private var stateColor: Color {
        switch file.state {
        case .restored: .secondary
        case .intendedBytesRemain, .externallyChanged, .missing, .unreadable: .orange
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        String(fingerprint.sha256.prefix(12)) + "… (\(fingerprint.byteCount) bytes)"
    }
}
