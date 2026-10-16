import AppKit
import ScholiumContracts
import SwiftUI

struct StorageSettingsView: View {
    private struct IndexConfirmationMeasurement {
        let requestID: UUID
        let usage: ScholiumStorageUsage?
    }

    @State private var indexConfirmationMeasurement: IndexConfirmationMeasurement?

    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @StateObject private var model: StorageSettingsModel

    init(capabilities: StorageSettingsCapabilities?) {
        _model = StateObject(wrappedValue: StorageSettingsModel(capabilities: capabilities))
    }

    private var selectedAssignment: TriptychAssignment? {
        settingsModel.registeredTriptychs.first { $0.id == settingsModel.selectedTriptychID }
    }

    private var selectedTriptychName: String {
        selectedAssignment.map { settingsTriptychLabel($0, among: settingsModel.registeredTriptychs) } ?? ""
    }

    var body: some View {
        Form {
            overview
            if model.isAvailable {
                caches
                index
                if let assignment = selectedAssignment {
                    StorageChangesHistorySettingsSection(triptychID: assignment.id, triptychName: selectedTriptychName)
                        .disabled(model.isPerforming)
                }
                chats
                protectedData
            }
        }
        .scholiumSettingsFormStyle()
        .scholiumSettingsSearchDestination()
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.storage")
        .task(id: isPaneActive) {
            model.setPaneActive(isPaneActive)
            guard isPaneActive else { return }
            synchronizeTarget()
            await model.measureIfNeeded()
        }
        .onDisappear { model.setPaneActive(false) }
        .onChange(of: settingsModel.selectedTriptychID) { _, _ in synchronizeTarget() }
        .onChange(of: selectedAssignment?.triptych.name) { _, _ in synchronizeTarget() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { model.confirmation != nil },
                set: { if !$0 { model.dismissConfirmation() } }
            ), titleVisibility: .visible
        ) {
            if let request = model.confirmation {
                Button(confirmationAction(request), role: confirmationRole(request)) { model.confirm(request) }
                Button("Cancel", role: .cancel) { model.dismissConfirmation() }
            }
        } message: {
            if let request = model.confirmation { confirmationMessage(request) }
        }
    }

    private var overview: some View {
        Section {
            if model.inventory != nil {
                LabeledContent("Measured App Storage") {
                    Text(storageBytes(model.measuredBytes))
                        .accessibilityIdentifier("scholium.settings.storage.total")
                }
                Text("Logical file sizes on this Mac. Research folders and Agent Runtime are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.unreadableEntries > 0 || model.skippedEntries > 0 {
                    Text("\(model.unreadableEntries) unreadable entries; \(model.skippedEntries) skipped entries. The measured total is incomplete.")
                        .textSelection(.enabled)
                        .accessibilityIdentifier("scholium.settings.storage.incomplete")
                }
                if let inventory = model.inventory {
                    LabeledContent("Measured") { Text(inventory.measuredAt, style: .time) }
                }
            } else if !model.isAvailable {
                Text("Storage management is unavailable in this Settings session.")
            }
            HStack {
                Button("Refresh Storage Usage") { Task { await model.refreshInventory() } }
                    .disabled(!model.isAvailable || model.isMeasuring || model.isBusy)
                    .accessibilityIdentifier("scholium.settings.storage.refresh")
                if let root = model.inventory?.rootURL {
                    Button("Show App Storage in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                }
                if model.isMeasuring { ProgressView("Measuring Storage…").controlSize(.small) }
            }
            feedback(for: .overview)
        } header: {
            Text("App Storage — This Mac")
        }
        .id(SettingsSection.storageOverview)
    }

    private var caches: some View {
        Section("Caches") {
            usageRow(.temporaryFiles, "Temporary Files")
            safeAction(.clearTemporaryFiles, "Clear Temporary Files")
            usageRow(.sourceProjectionCache, "Note Cache")
            Text("Cached Note data is recreated from authorized source when needed.")
                .font(.caption).foregroundStyle(.secondary)
            safeAction(.clearProjectionCache, "Clear Note Cache")
            safeAction(.cleanRetiredDerivedState, "Clean Retired Indexes and Caches")
            feedback(for: .caches)
        }
        .id(SettingsSection.storageCache)
    }

    private var index: some View {
        Section("Search Index") {
            usageRow(.searchIndexes, "All Search Indexes")
            scopePicker
            if let id = selectedAssignment?.id {
                LabeledContent("Selected Triptych’s Index") {
                    if let usage = model.inventory?.searchIndexesByTriptych[id] {
                        Text(storageBytes(usage.byteCount))
                    } else {
                        Text("Not Measured").foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("scholium.settings.storage.selectedIndexSize")
                if let usage = model.inventory?.searchIndexesByTriptych[id],
                    usage.unreadableEntries > 0 || usage.skippedEntries > 0
                {
                    Text("\(usage.unreadableEntries) unreadable entries; \(usage.skippedEntries) skipped entries. The measured total is incomplete.")
                        .textSelection(.enabled)
                }
            }
            if selectedAssignment != nil {
                Text("Index actions apply to \(selectedTriptychName).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Select a registered Triptych to manage its index and history.")
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { indexActions }
                VStack(alignment: .leading) { indexActions }
            }
            .disabled(model.isBusy || model.isMeasuring || selectedAssignment == nil || !model.isAvailable)
            feedback(for: .index)
        }
        .id(SettingsSection.storageIndex)
    }

    private var scopePicker: some View {
        Picker(
            "Triptych",
            selection: Binding(
                get: { settingsModel.selectedTriptychID },
                set: { id in if let id { Task { await settingsModel.activateTriptych(id: id) } } }
            )
        ) {
            ForEach(settingsModel.registeredTriptychs) { assignment in
                Text(settingsTriptychLabel(assignment, among: settingsModel.registeredTriptychs)).tag(Optional(assignment.id))
            }
        }
        .disabled(model.isBusy || settingsModel.registeredTriptychs.isEmpty)
        .accessibilityIdentifier("scholium.settings.storage.triptychScope")
    }

    @ViewBuilder
    private var indexActions: some View {
        Button("Rebuild Index…") { requestIndexAction(.rebuildIndex) }
            .accessibilityIdentifier("scholium.settings.storage.rebuildIndex")
        Button("Clear Index…", role: .destructive) { requestIndexAction(.clearIndex) }
            .accessibilityIdentifier("scholium.settings.storage.clearIndex")
    }

    private var chats: some View {
        Section("Archived Conversations") {
            usageRow(.chatHistory, "All Chat History")
            usageRow(.chatMaterials, "Chat Materials")
            if selectedAssignment != nil {
                Text("For \(selectedTriptychName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Delete only archived conversations in the selected Triptych. Active conversations remain available.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Delete Archived Conversations…", role: .destructive) {
                Task { await model.prepareArchivedChatDeletion() }
            }
            .disabled(model.isBusy || model.isMeasuring || selectedAssignment == nil)
            .accessibilityIdentifier("scholium.settings.storage.deleteArchivedChats")
            feedback(for: .chat)
        }
        .id(SettingsSection.storageChatHistory)
    }

    private var protectedData: some View {
        Section("Research and Configuration Data") {
            usageRow(.researchHistory, "Changes and Review Data")
            usageRow(.recovery, "Recovery and Operation Data")
            usageRow(.configuration, "Configuration and Saved State")
            usageRow(.unclassified, "Other App Data")
            Text("These records can preserve comparisons, Undo, recovery and preferences. Cache and index cleanup preserves them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func feedback(for scope: StorageSettingsActivityScope) -> some View {
        if model.isBusy, model.activityScope == scope {
            if model.isPerforming {
                ProgressView("Updating App Storage…")
                    .accessibilityIdentifier("scholium.settings.storage.progress")
            } else {
                ProgressView("Inspecting Archived Conversations…")
            }
        }
        if let operation = model.completedOperation, operationScope(operation) == scope {
            operationResult(operation)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.settings.storage.result")
        }
        if scope == .chat, let notice = model.notice { Text(notice).textSelection(.enabled) }
        if model.activityScope == scope, let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                .accessibilityIdentifier("scholium.settings.storage.error")
            Button("Retry Measuring Storage") { Task { await model.refreshInventory() } }
                .disabled(model.isBusy || model.isMeasuring)
        }
    }

    private func operationScope(_ operation: StorageSettingsCompletedOperation) -> StorageSettingsActivityScope {
        switch operation {
        case .storage(let result, _):
            result.action == .clearIndex || result.action == .rebuildIndex ? .index : .caches
        case .archivedChats: .chat
        }
    }

    private func usageRow(_ category: ScholiumStorageCategory, _ title: LocalizedStringKey) -> some View {
        LabeledContent(title) {
            if let usage = model.inventory?.usages.first(where: { $0.category == category }) {
                Text(storageBytes(usage.byteCount))
            } else {
                Text("Not Measured").foregroundStyle(.secondary)
            }
        }
    }

    private func safeAction(_ action: ScholiumStorageAction, _ label: LocalizedStringKey) -> some View {
        Button(label) { Task { await model.performSafeAction(action) } }
            .disabled(model.isBusy || model.isMeasuring || model.inventory == nil)
            .accessibilityIdentifier("scholium.settings.storage.\(action.rawValue)")
    }

    private func requestIndexAction(_ action: ScholiumStorageAction) {
        model.requestIndexAction(action)
        guard let request = model.confirmation, case .index = request.intent else { return }
        indexConfirmationMeasurement = IndexConfirmationMeasurement(
            requestID: request.id, usage: model.inventory?.searchIndexesByTriptych[request.triptychID])
    }

    private func indexSizeDescription(for request: StorageSettingsConfirmation) -> String {
        guard let measurement = indexConfirmationMeasurement, measurement.requestID == request.id,
            let usage = measurement.usage
        else { return ScholiumL10n.string("Index size has not been measured.") }
        let size = ScholiumL10n.string("Measured index size: \(storageBytes(usage.byteCount)).")
        guard usage.unreadableEntries > 0 || usage.skippedEntries > 0 else { return size }
        return size + " "
            + ScholiumL10n.string(
                "\(usage.unreadableEntries) unreadable entries; \(usage.skippedEntries) skipped entries. The measured total is incomplete.")
    }

    private func synchronizeTarget() {
        model.selectTriptych(id: selectedAssignment?.id, name: selectedTriptychName)
    }

    private var confirmationTitle: LocalizedStringKey {
        guard let request = model.confirmation else { return "Storage" }
        switch request.intent {
        case .index(.rebuildIndex, _): return "Rebuild This Triptych’s Index?"
        case .index: return "Clear This Triptych’s Index?"
        case .archivedChats: return "Delete Archived Conversations?"
        }
    }

    private func confirmationAction(_ request: StorageSettingsConfirmation) -> LocalizedStringKey {
        switch request.intent {
        case .index(.rebuildIndex, _): "Rebuild Index"
        case .index: "Clear Index"
        case .archivedChats: "Delete Archived Conversations"
        }
    }

    private func confirmationRole(_ request: StorageSettingsConfirmation) -> ButtonRole? {
        if case .index(.rebuildIndex, _) = request.intent { return nil }
        return .destructive
    }

    @ViewBuilder
    private func confirmationMessage(_ request: StorageSettingsConfirmation) -> some View {
        switch request.intent {
        case .index(.rebuildIndex, _):
            Text(
                "Rebuild the search index for \(request.triptychName) from authorized current Notes. Search may be unavailable while rebuilding. \(indexSizeDescription(for: request)) Note source, research attachments, Changes history and recovery records are preserved."
            )
        case .index:
            Text(
                "Clear the search index for \(request.triptychName). Search remains unavailable until you choose Rebuild Index or reopen this Triptych. \(indexSizeDescription(for: request)) Note source, research attachments, Changes history and recovery records are preserved."
            )
        case .archivedChats(let plan):
            Text(
                "Permanently delete \(plan.conversationIDs.count) archived conversations in \(request.triptychName) (about \(storageBytes(plan.estimatedByteCount)) of conversation data). Unreferenced managed Chat-material copies are also released. This cannot be undone. Note source, research attachments, recovery records and active conversations are preserved."
            )
        }
    }

    @ViewBuilder
    private func operationResult(_ operation: StorageSettingsCompletedOperation) -> some View {
        switch operation {
        case .storage(let result, let name):
            if let name { Text("For \(name)") }
            if result.action == .rebuildIndex {
                Text("Index rebuild completed.")
            } else if result.action == .clearIndex {
                Text("Index cleared. Choose Rebuild Index or reopen the Triptych.")
            }
            if result.action != .clearIndex && result.action != .rebuildIndex {
                Text("Removed \(result.cleanup.removedFiles) files · \(storageBytes(result.cleanup.removedBytes))")
            }
            if result.cleanup.preservedFiles > 0 || result.cleanup.failedFiles > 0 || result.cleanup.busyDirectories > 0 {
                Text(
                    "\(result.cleanup.preservedFiles) files preserved; \(result.cleanup.failedFiles) files could not be removed; \(result.cleanup.busyDirectories) locations in use."
                )
            }
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                Label(ScholiumErrorLocalization.storageWarning(warning), systemImage: "exclamationmark.triangle").textSelection(.enabled)
            }
        case .archivedChats(let result, let name):
            Text("For \(name)")
            Text("Deleted \(result.removedConversations) archived conversations.")
            if let issue = result.materialCleanupIssue {
                Label(issue, systemImage: "exclamationmark.triangle").textSelection(.enabled)
            }
        }
    }
}

private func storageBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
