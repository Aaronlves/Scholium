import AppKit
import ScholiumContracts
import SwiftUI

struct WorkspaceSettingsView: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let openTriptych: (UUID) -> Void
    let newTriptych: () -> Void

    var body: some View {
        ScholiumSettingsPaneHost(selection: settingsModel.selectedTriptychID) { id in
            if let id {
                WorkspacePathEditor(targetTriptychID: id) { registrationSection }
            } else {
                Form {
                    registrationSection
                    if settingsModel.isRefreshing {
                        ProgressView("Loading Registered Triptychs")
                    } else if let error = settingsModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                        Button("Reload Triptych Registration") {
                            Task { await settingsModel.refresh() }
                        }
                    } else {
                        ScholiumContentStateView(
                            "No Triptych Registered",
                            detail: Text("Create a Triptych by choosing Analyses, Topics, and Works folders."),
                            indicator: .symbol("rectangle.3.group")
                        )
                    }
                }.scholiumSettingsFormStyle()
            }
        }
        .scholiumSettingsPaneSurface()
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            await settingsModel.refresh()
        }
    }

    private var registrationSection: some View {
        Section("Registered Triptychs") {
            triptychPicker
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumMetrics.Settings.rootSpacing) { triptychActions }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    triptychActions
                }
            }
        }.id(SettingsSection.workspaceRegistration)
    }

    private var selectedTriptychBinding: Binding<UUID?> {
        Binding(
            get: { settingsModel.selectedTriptychID },
            set: { value in
                guard let value else { return }
                Task { await settingsModel.activateTriptych(id: value) }
            }
        )
    }

    private var triptychPicker: some View {
        Picker("Triptych", selection: selectedTriptychBinding) {
            ForEach(settingsModel.registeredTriptychs) { assignment in
                Text(
                    settingsTriptychLabel(
                        assignment,
                        among: settingsModel.registeredTriptychs
                    )
                )
                .tag(Optional(assignment.id))
            }
        }
        .scholiumActivationPointer()
        .frame(maxWidth: 360)
        .disabled(settingsModel.registeredTriptychs.isEmpty)
        .accessibilityIdentifier("scholium.settings.triptychScope")
    }

    @ViewBuilder
    private var triptychActions: some View {
        Button("Open in New Window") {
            guard let selectedTriptychID = settingsModel.selectedTriptychID else { return }
            openTriptych(selectedTriptychID)
        }
        .scholiumActivationPointer()
        .disabled(settingsModel.selectedTriptychID == nil)

        Button("New Triptych…") {
            newTriptych()
        }
        .scholiumActivationPointer()
    }

}

private func settingsTriptychLabel(
    _ assignment: TriptychAssignment,
    among assignments: [TriptychAssignment]
) -> String {
    let duplicates = assignments.filter {
        $0.triptych.name.caseInsensitiveCompare(assignment.triptych.name) == .orderedSame
    }
    guard duplicates.count > 1,
        let works = assignment.vault(for: .output)
    else {
        return assignment.triptych.name
    }
    let parent = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        .deletingLastPathComponent().lastPathComponent
    return "\(assignment.triptych.name) — \(parent)"
}

private struct ChangesHistorySettingsSection: View {
    private struct ClearTarget {
        let id: UUID
        let name: String
    }

    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let triptychID: UUID
    let triptychName: String

    @State private var snapshot: WorkspaceChangesHistorySnapshot?
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var clearTarget: ClearTarget?
    @State private var loadGeneration = 0

    var body: some View {
        Section("Changes History — This Mac") {
            Text("For \(triptychName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(
                "Keep Reviewed History",
                selection: Binding(
                    get: { snapshot?.retention ?? .days90 },
                    set: { choice in
                        let targetID = triptychID
                        Task { await setRetention(choice, for: targetID) }
                    }
                )
            ) {
                Text("30 Days").tag(DocumentChangeRetention.days30)
                Text("90 Days").tag(DocumentChangeRetention.days90)
                Text("1 Year").tag(DocumentChangeRetention.days365)
                Text("Forever").tag(DocumentChangeRetention.forever)
            }
            .pickerStyle(.menu)
            .disabled(isLoading || isMutating || snapshot == nil)
            .accessibilityIdentifier("scholium.settings.changesRetention")

            if let snapshot {
                LabeledContent("Reviewed History") {
                    Text("\(snapshot.usage.count) records · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.usage.byteCount), countStyle: .file))")
                }
                if snapshot.usage.protectedByteCount > 0 {
                    LabeledContent("Comparison & Operation Data") {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: Int64(snapshot.usage.protectedByteCount),
                                countStyle: .file
                            ))
                    }
                    .help("Saved comparison baselines and Agent receipts needed for Undo or recovery can remain after reviewed history is cleared.")
                }
            } else if isLoading {
                ProgressView("Loading Changes History…")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Retry") { Task { await load() } }
                    .disabled(isLoading || isMutating)
            }

            Button("Clear Reviewed History…", role: .destructive) {
                clearTarget = ClearTarget(id: triptychID, name: triptychName)
            }
            .disabled(isLoading || isMutating || (snapshot?.usage.count ?? 0) == 0)
            .accessibilityIdentifier("scholium.settings.clearChangesHistory")
        }
        .id(SettingsSection.workspaceChangesHistory)
        .task(id: triptychID) { await load() }
        .onReceive(settingsModel.changesHistoryUpdates) { changedID in
            if changedID == triptychID { Task { await load() } }
        }
        .onChange(of: triptychID) { _, _ in
            loadGeneration &+= 1
            snapshot = nil
            errorMessage = nil
            isLoading = true
            clearTarget = nil
        }
        .confirmationDialog(
            "Clear Reviewed History for This Triptych?",
            isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            )
        ) {
            Button("Clear Reviewed History", role: .destructive) {
                guard let target = clearTarget else { return }
                clearTarget = nil
                Task { await clearHistory(for: target.id) }
            }
            Button("Cancel", role: .cancel) { clearTarget = nil }
        } message: {
            Text(
                "Reviewed comparisons for \(clearTarget?.name ?? triptychName) on this Mac will be deleted. Current Note text and pending Changes, including their starting versions, remain available."
            )
        }
    }

    private func load() async {
        let targetID = triptychID
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await settingsModel.changesHistory(triptychID: targetID)
            guard triptychID == targetID, loadGeneration == generation else { return }
            snapshot = loaded
        } catch is CancellationError {
            return
        } catch {
            guard triptychID == targetID, loadGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setRetention(
        _ choice: DocumentChangeRetention,
        for targetID: UUID
    ) async {
        guard targetID == triptychID, snapshot != nil, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            let changed = try await settingsModel.setChangesHistoryRetention(
                choice, triptychID: targetID
            )
            if targetID == triptychID { snapshot = changed }
        } catch {
            if targetID == triptychID {
                let issue = error.localizedDescription
                await load()
                errorMessage = issue
            }
        }
        isMutating = false
    }

    private func clearHistory(for targetID: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            let cleared = try await settingsModel.clearChangesHistory(triptychID: targetID)
            if targetID == triptychID { snapshot = cleared }
        } catch {
            if targetID == triptychID {
                let issue = error.localizedDescription
                await load()
                errorMessage = issue
            }
        }
        isMutating = false
    }
}

private struct WorkspacePathEditor<Registration: View>: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel

    let targetTriptychID: UUID
    @ViewBuilder var registration: () -> Registration

    @State private var paperAnalysisURL: URL?
    @State private var topicKnowledgeURL: URL?
    @State private var outputURL: URL?
    @State private var portableContainerURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var loadedCurrentValues = false
    @State private var triptychName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                registration()
                Section("Triptych Details") {
                    LabeledContent("Name") {
                        TextField("Name", text: $triptychName)
                            .labelsHidden()
                            .accessibilityIdentifier("scholium.triptychName")
                    }
                    .id(SettingsSection.workspaceName)
                    WorkspaceFolderRow(
                        title: "Analyses",
                        url: $paperAnalysisURL
                    )
                    .id(SettingsSection.workspaceFolders)
                    WorkspaceFolderRow(
                        title: "Topics",
                        url: $topicKnowledgeURL
                    )
                    WorkspaceFolderRow(
                        title: "Works",
                        url: $outputURL
                    )
                }.disabled(!loadedCurrentValues)

                Section("Portable Triptych Data") {
                    PortableControlFolderRow(
                        worksURL: outputURL,
                        containerURL: $portableContainerURL
                    )
                    Text(
                        "Scholium stores the small portable .scholium folder beside Works. macOS therefore asks once for access to the folder containing Works; it is not added as a fourth vault."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }.id(SettingsSection.workspacePortable)
                    .disabled(!loadedCurrentValues)

                if loadedCurrentValues { PortableSettingsRecoverySection(triptychID: targetTriptychID) }

                ChangesHistorySettingsSection(
                    triptychID: targetTriptychID,
                    triptychName: settingsModel.registeredTriptychs.first {
                        $0.id == targetTriptychID
                    }.map { settingsTriptychLabel($0, among: settingsModel.registeredTriptychs) }
                        ?? targetTriptychID.uuidString
                )

            }
            .scholiumSettingsFormStyle()
            .scholiumSettingsSearchDestination()

            if !loadedCurrentValues {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    if settingsModel.isRefreshing {
                        ProgressView("Loading Registered Triptychs")
                    } else {
                        if let error = settingsModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                        }
                        Button("Reload Triptych Registration") {
                            Task { await settingsModel.refresh() }
                        }
                    }
                }
                .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityLabel("Workspace error: \(errorMessage)")
            } else if let recoveryMessage = settingsModel.workspaceRecoveryMessage {
                Label(recoveryMessage, systemImage: "folder.badge.questionmark")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityLabel("Workspace access: \(recoveryMessage)")
            }

            HStack {
                Spacer()
                Button("Save Triptych") { save() }
                    .buttonStyle(.bordered)
                    .scholiumSettingsDefaultAction()
                    .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
        }
        .accessibilityIdentifier("scholium.triptychSetup")
        .onChange(of: targetAssignment) { _, _ in loadCurrentValuesIfNeeded() }
        .task {
            loadCurrentValuesIfNeeded()
            await settingsModel.refresh()
            loadCurrentValuesIfNeeded()
            await loadPortableContainerIfAvailable()
        }
        .onChange(of: outputURL) { oldValue, newValue in
            let oldParent = oldValue?.deletingLastPathComponent().standardizedFileURL.path
            let newParent = newValue?.deletingLastPathComponent().standardizedFileURL.path
            if oldParent != newParent {
                portableContainerURL = nil
            }
            Task { await loadPortableContainerIfAvailable() }
        }
    }

    private var allFoldersSelected: Bool {
        paperAnalysisURL != nil && topicKnowledgeURL != nil && outputURL != nil
    }

    private var canSave: Bool {
        guard allFoldersSelected,
            let outputURL,
            let portableContainerURL
        else { return false }
        return outputURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            == portableContainerURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func loadCurrentValuesIfNeeded() {
        guard !loadedCurrentValues, targetAssignment != nil else { return }
        loadedCurrentValues = true
        paperAnalysisURL = assignedURL(for: .paperAnalysis)
        topicKnowledgeURL = assignedURL(for: .topicKnowledge)
        outputURL = assignedURL(for: .output)
        triptychName = targetAssignment?.triptych.name ?? ""
    }

    private func loadPortableContainerIfAvailable() async {
        guard let outputURL else {
            portableContainerURL = nil
            return
        }
        let registered = await settingsModel.portableContainerURL(for: outputURL)
        guard self.outputURL?.standardizedFileURL == outputURL.standardizedFileURL else { return }
        if let registered { portableContainerURL = registered }
    }

    private var targetAssignment: TriptychAssignment? {
        settingsModel.registeredTriptychs.first(where: { $0.id == targetTriptychID })
    }

    private func assignedURL(for slot: WorkspaceVaultSlot) -> URL? {
        targetAssignment?.vault(for: slot).map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
        }
    }

    private func save() {
        guard let paperAnalysisURL, let topicKnowledgeURL, let outputURL else { return }
        guard let portableContainerURL else {
            errorMessage = String(
                localized: "Authorize the folder containing Works before saving this Triptych.",
                table: "Localizable", bundle: .module)
            return
        }
        let submittedName = triptychName
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await settingsModel.configureTriptych(
                    paperAnalysisURL: paperAnalysisURL,
                    topicKnowledgeURL: topicKnowledgeURL,
                    outputURL: outputURL,
                    portableContainerURL: portableContainerURL,
                    triptychID: targetTriptychID,
                    triptychName: submittedName
                )
                settingsModel.workspaceRecoveryMessage = nil
                isSaving = false
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PortableControlFolderRow: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    let worksURL: URL?
    @Binding var containerURL: URL?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                Image(systemName: "folder.badge.gearshape")
                    .scholiumSymbolStyle(.prominent)
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text("Folder Containing Works")
                        .font(.body)
                    Text("Authorizes portable settings stored beside Works")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: containerURL?.path(percentEncoded: false) ?? ScholiumL10n.string("Authorization required"))
                        .font(.caption)
                        .foregroundStyle(containerURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: ScholiumMetrics.Settings.trailingControlMinimumSpacing)

                Button(containerURL == nil ? "Authorize…" : "Authorize Again…") {
                    authorizeFolder()
                }
                .disabled(worksURL == nil)
                .accessibilityLabel("Authorize folder containing Works")
            }
            if let selectionError {
                Text(selectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityIdentifier("scholium.portableControlAccess")
    }

    private func authorizeFolder() {
        guard
            let expected = worksURL?
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
        else { return }
        let request = ScholiumFileSelectionRequest(
            title: ScholiumL10n.string("Authorize the Folder Containing Works"),
            message: String(
                format: ScholiumL10n.string(
                    "Choose '%@' so Scholium can use the portable .scholium folder beside Works."
                ),
                locale: Locale.current,
                expected.lastPathComponent
            ),
            prompt: ScholiumL10n.string("Authorize"),
            initialDirectoryURL: expected.deletingLastPathComponent(),
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expected,
                rejectionMessage: ScholiumL10n.string(
                    "Choose the folder containing Works shown above."
                )
            )
        )
        Task { @MainActor in
            do {
                guard
                    let selected =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                selectionError = nil
                containerURL = selected
            } catch is CancellationError {
                return
            } catch {
                selectionError = error.localizedDescription
            }
        }
    }
}

struct WorkspaceFolderRow: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    let title: String
    @Binding var url: URL?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text(localizedTitle)
                        .font(.body)
                    Text(url?.path(percentEncoded: false) ?? ScholiumL10n.string("No folder selected"))
                        .font(.caption)
                        .foregroundStyle(url == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url?.path(percentEncoded: false) ?? ScholiumL10n.string("Choose a folder"))
                }

                Spacer(minLength: ScholiumMetrics.Settings.trailingControlMinimumSpacing)

                Button(url == nil ? ScholiumL10n.string("Choose…") : ScholiumL10n.string("Change…")) {
                    chooseFolder()
                }
                .accessibilityLabel(Text(verbatim: chooseFolderAccessibilityLabel))
            }
            if let selectionError {
                Text(selectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
    }

    private var localizedTitle: String {
        ScholiumL10n.dynamicString(title)
    }

    private var chooseFolderAccessibilityLabel: String {
        String(
            format: ScholiumL10n.string("Choose %@ Folder", locale: Locale.current),
            locale: Locale.current,
            localizedTitle
        )
    }

    private func chooseFolder() {
        var initialDirectoryURL = url?.deletingLastPathComponent()
        #if DEBUG
            if initialDirectoryURL == nil,
                let testDirectory = ProcessInfo.processInfo.environment[
                    "SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"
                ],
                !testDirectory.isEmpty
            {
                initialDirectoryURL = URL(fileURLWithPath: testDirectory, isDirectory: true)
            }
        #endif
        let request = ScholiumFileSelectionRequest(
            title: String(
                format: ScholiumL10n.string("Choose %@ Folder"),
                locale: Locale.current,
                localizedTitle
            ),
            prompt: ScholiumL10n.string("Choose"),
            initialDirectoryURL: initialDirectoryURL,
            kind: .directory(canCreateDirectories: true)
        )
        Task { @MainActor in
            do {
                guard
                    let selected =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                selectionError = nil
                url = selected
            } catch is CancellationError {
                return
            } catch {
                selectionError = error.localizedDescription
            }
        }
    }
}
