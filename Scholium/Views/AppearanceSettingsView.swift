import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var store: CSSSnippetStore
    @StateObject private var fontCatalog = ScholiumSettingsFontCatalog()
    @State private var draft: DocumentAppearanceProfile?
    @State private var importError: String?
    @State private var showRename = false
    @State private var showDeleteConfirmation = false
    @State private var showRestoreDefaultConfirmation = false
    @State private var confirmsAppearanceRecovery = false
    @State private var confirmsSnippetRecovery = false
    @State private var showDiscardChangesConfirmation = false
    private enum ProfileSelection {
        case existing(UUID)
        case create
        case duplicate(UUID)
    }
    @State private var pendingProfileSelection: ProfileSelection?
    @State private var nameDraft = ""

    @State private var confirmsConfigurationReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draftBinding {
                appearanceSectionContent(profile: draftBinding)
            } else {
                Form {
                    appearanceRecoverySection
                    Section("CSS Snippets") { cssSnippetsContent }.id(SettingsSection.appearanceCSS)
                    configurationFileSection.id(SettingsSection.appearanceFile)
                }
                .scholiumSettingsFormStyle()
                .scholiumSettingsSearchDestination()
            }

            appearanceStatus
            appearanceSaveActions
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.appearance.form")
        .task { await fontCatalog.loadIfNeeded() }
        .onAppear { if draft == nil { loadSelectedDraft() } }
        .onChange(of: store.selectedAppearanceProfileID) { _, _ in loadSelectedDraft() }
        .onChange(of: store.appearanceProfiles) { previous, _ in
            if let draft, let saved = store.selectedAppearanceProfile,
                draft.id == saved.id,
                let baseline = previous.first(where: { $0.id == draft.id }),
                draft.settings != baseline.settings
            {
                // A successful rename or background refresh cannot erase an
                // unsaved typography draft. Save still belongs to the store.
                self.draft?.name = saved.name
            } else {
                loadSelectedDraft()
            }
        }
        .onChange(of: store.appearanceReloadRevision) { _, _ in loadSelectedDraft() }
        .confirmationDialog(
            "Reload Appearance Configuration?", isPresented: $confirmsConfigurationReload,
            titleVisibility: .visible
        ) {
            Button("Reload", role: .destructive) { store.reloadAppearanceConfiguration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Reloading replaces your unsaved appearance draft with the configuration file. An invalid file leaves the draft unchanged."
            )
        }
        .alert("Rename Appearance", isPresented: $showRename) {
            TextField("Configuration name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.renameAppearance(id, to: nameDraft)
            }
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Appearance?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.removeAppearance(id)
            }
        } message: {
            Text(
                "This removes the selected configuration from this Mac. Research documents are not changed."
            )
        }
        .confirmationDialog("Restore Default Appearance?", isPresented: $confirmsAppearanceRecovery, titleVisibility: .visible) {
            Button("Restore Defaults", role: .destructive) { store.restoreAppearanceDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Replace saved appearance profiles with a default profile and discard the current appearance draft. The previous configuration file is preserved separately. CSS snippets and research files are unchanged."
            )
        }
        .confirmationDialog("Recover CSS Snippet Settings?", isPresented: $confirmsSnippetRecovery, titleVisibility: .visible) {
            Button("Recover CSS Snippet Settings", role: .destructive) { store.restoreStyleSnippetDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Restore snippet settings with all snippets disabled. The previous settings file is preserved separately. CSS files, appearance profiles and research files are unchanged."
            )
        }
        .confirmationDialog(
            "Restore Default Appearance?",
            isPresented: $showRestoreDefaultConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                draft?.settings = DocumentAppearanceSettings.defaultSettings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the current draft with Scholium’s built-in document appearance. Choose Save to keep it."
            )
        }
        .confirmationDialog(
            "Discard Unsaved Appearance Changes?",
            isPresented: $showDiscardChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Switch", role: .destructive) {
                guard let id = pendingProfileSelection else { return }
                pendingProfileSelection = nil
                performProfileSelection(id)
            }
            Button("Cancel", role: .cancel) {
                pendingProfileSelection = nil
            }
        } message: {
            Text(
                "The selected appearance has unsaved changes. Switching configurations will discard them.")
        }
    }

    @ViewBuilder
    private func appearanceSectionContent(
        profile: Binding<DocumentAppearanceProfile>
    ) -> some View {
        Form {
            configurationSection.id(SettingsSection.appearanceProfile).disabled(!store.canModifyAppearance)
            appearanceRecoverySection
            AppearanceReadingEditor(profile: profile, fontCatalog: fontCatalog).disabled(!store.canModifyAppearance && !store.canRepairAppearance)
            TypographySettingsView(profile: profile, fontCatalog: fontCatalog).disabled(!store.canModifyAppearance && !store.canRepairAppearance)
            AppearanceSourceEditor(profile: profile, fontCatalog: fontCatalog).disabled(!store.canModifyAppearance && !store.canRepairAppearance)
            Section("CSS Snippets") { cssSnippetsContent }.id(SettingsSection.appearanceCSS)
            configurationFileSection.id(SettingsSection.appearanceFile)
        }
        .scholiumSettingsFormStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSettingsSearchDestination()
        .accessibilityIdentifier("scholium.settings.appearance")
    }

    @ViewBuilder
    private var appearanceRecoverySection: some View {
        if let error = store.appearanceError {
            Section("Appearance Recovery") {
                Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                Button("Restore Default Appearance…") { confirmsAppearanceRecovery = true }
                    .disabled(store.isRestoringAppearance)
                    .accessibilityIdentifier("scholium.settings.appearance.recover")
            }
        }
    }

    private var configurationFileSection: some View {
        Section("Configuration File") {
            HStack {
                Button("Show in Finder…") { store.revealAppearanceConfiguration() }
                Spacer()
                Button("Reload") {
                    if hasUnsavedChanges {
                        confirmsConfigurationReload = true
                    } else {
                        store.reloadAppearanceConfiguration()
                    }
                }
                .accessibilityIdentifier("scholium.settings.appearance.reload")
                Button("Configuration Guide…") {
                    if let url = Bundle.module.url(
                        forResource: "AppearanceConfiguration", withExtension: "md")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appearanceStatus: some View {
        if let reason = store.safeModeReason {
            Label("CSS Safe Mode: \(reason)", systemImage: "exclamationmark.shield.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        }
        if let storeError = store.storeError {
            Label(storeError, systemImage: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.red)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                .accessibilityIdentifier("settings.css.store-error")
        }
        if let importError {
            Label(importError, systemImage: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.red)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        }
    }

    private var selectedProfileID: Binding<UUID?> {
        Binding(
            get: { store.selectedAppearanceProfileID },
            set: { id in
                guard let id else { return }
                requestProfileSelection(.existing(id))
            }
        )
    }

    private var configurationSection: some View {
        Section {
            LabeledContent("Profile") {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    appearancePicker
                    appearanceManagementMenu
                }
            }
        } footer: {
            Text("Saved on this Mac")
        }
    }

    private var appearanceSaveActions: some View {
        HStack(spacing: 8) {
            if hasUnsavedChanges {
                Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert to Saved") { loadSelectedDraft() }
                .disabled(!hasUnsavedChanges)
            if store.canRepairAppearance {
                Button("Repair Saved Profile") {
                    guard let draft else { return }
                    store.repairAppearanceProfile(draft)
                }
                .disabled(store.isRestoringAppearance)
                .accessibilityIdentifier("scholium.settings.appearance.repair")
            }
            Button("Save Appearance") {
                guard let draft else { return }
                store.updateAppearance(draft)
            }
            .scholiumSettingsDefaultAction()
            .disabled(!hasUnsavedChanges || !store.canModifyAppearance)
            .accessibilityLabel("Save Appearance")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var cssSnippetsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "Add .css files to the managed folder, or import one. Changes are detected automatically and apply to Review and Edit after validation; Source remains exact."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Callouts: .callout, .callout-title, .callout-body, and .callout-<role>.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button {
                    store.revealManagedFolder()
                } label: {
                    Label("Open CSS Folder", systemImage: "folder")
                }

                Button {
                    store.reloadSnippets()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Spacer(minLength: 0)

                Button("Import CSS Snippet…") { importSnippet() }
                    .disabled(!store.canModify)
            }

            Divider()

            if let error = store.snippetError {
                Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                Button("Recover CSS Snippet Settings…") { confirmsSnippetRecovery = true }
                    .disabled(store.isRestoringSnippets)
                    .accessibilityIdentifier("scholium.settings.css.recover")
            }

            ForEach(store.snippets) { snippet in
                CSSSnippetRow(
                    snippet: snippet,
                    error: store.validationErrors[snippet.id],
                    store: store
                ).disabled(!store.canModify)
            }

            if store.snippets.isEmpty {
                Text("No CSS snippets yet. Open the folder or import a file to add one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button("Disable All Snippets") { store.disableAll() }
                .disabled(store.enabledCount == 0 || !store.canModify)
        }
    }

    private var appearancePicker: some View {
        Picker("Configuration", selection: selectedProfileID) {
            ForEach(store.appearanceProfiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
        .scholiumActivationPointer()
        .labelsHidden()
        .frame(width: ScholiumMetrics.Settings.appearancePickerWidth, alignment: .leading)
    }

    private var appearanceManagementMenu: some View {
        Menu {
            Button("New Appearance") { requestProfileSelection(.create) }
            Button("Duplicate Appearance") {
                guard let id = store.selectedAppearanceProfileID else { return }
                requestProfileSelection(.duplicate(id))
            }
            .disabled(store.selectedAppearanceProfileID == nil)
            Button("Rename Appearance…") { beginRename() }
                .disabled(store.selectedAppearanceProfileID == nil)
            Button("Restore Default Appearance…") {
                showRestoreDefaultConfirmation = true
            }
            .disabled(store.selectedAppearanceProfileID == nil)
            Divider()
            Button("Delete Appearance…", role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(store.appearanceProfiles.count <= 1)
        } label: {
            Label("Manage", systemImage: "ellipsis.circle")
        }
        .scholiumActivationPointer()
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("scholium.appearance.manage")
    }

    private var draftBinding: Binding<DocumentAppearanceProfile>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft! },
            set: { draft = $0 }
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let draft, let selected = store.selectedAppearanceProfile else { return false }
        return draft != selected
    }

    private func loadSelectedDraft() {
        draft = store.selectedAppearanceProfile
    }

    private func requestProfileSelection(_ selection: ProfileSelection) {
        if hasUnsavedChanges {
            pendingProfileSelection = selection
            showDiscardChangesConfirmation = true
        } else {
            performProfileSelection(selection)
        }
    }

    private func performProfileSelection(_ selection: ProfileSelection) {
        switch selection {
        case .existing(let id): selectProfile(id)
        case .create: store.createAppearance()
        case .duplicate(let id): store.duplicateAppearance(id)
        }
    }

    private func selectProfile(_ id: UUID) {
        store.selectAppearance(id)
        if let profile = store.appearanceProfiles.first(where: { $0.id == id }) {
            draft = profile
        }
    }

    private func beginRename() {
        guard let selected = store.selectedAppearanceProfile else { return }
        nameDraft = selected.name
        showRename = true
    }

    private func importSnippet() {
        let request = ScholiumFileSelectionRequest(
            title: ScholiumL10n.string("Import CSS Snippet"),
            prompt: ScholiumL10n.string("Import"),
            kind: .files(
                allowedContentTypes: [
                    UTType(filenameExtension: "css") ?? .plainText
                ]
            )
        )
        Task { @MainActor in
            do {
                guard
                    let url =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                try await store.importSnippet(from: url)
                importError = nil
            } catch is CancellationError {
                return
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct CSSSnippetRow: View {
    let snippet: CSSSnippetRecord
    let error: String?
    @ObservedObject var store: CSSSnippetStore
    @State private var showRename = false
    @State private var nameDraft = ""

    var body: some View {
        HStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
            Toggle(
                isOn: Binding(
                    get: { snippet.isEnabled },
                    set: { store.setEnabled($0, for: snippet.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text(snippet.name)
                        .lineLimit(1)
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        Text(snippet.isEnabled ? "Enabled" : "Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: ScholiumMetrics.Settings.rowActionMinimumSpacing)

            Button {
                store.move(snippet.id, by: -1)
            } label: {
                Label("Move Earlier", systemImage: "chevron.up")
            }
            .labelStyle(.iconOnly)
            .help("Move Earlier")

            Button {
                store.move(snippet.id, by: 1)
            } label: {
                Label("Move Later", systemImage: "chevron.down")
            }
            .labelStyle(.iconOnly)
            .help("Move Later")

            Menu {
                Button("Rename…") {
                    nameDraft = snippet.name
                    showRename = true
                }
                Button("Duplicate") { store.duplicate(snippet.id) }
                Button("Edit Managed Copy") { store.editManagedCopy(snippet.id) }
                Button("Reload from Disk") { store.reload(snippet.id) }
                Divider()
                Button("Remove Snippet", role: .destructive) { store.remove(snippet.id) }
            } label: {
                Label("Snippet Actions", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, ScholiumMetrics.Settings.rowVerticalInset)
        .alert("Rename CSS Snippet", isPresented: $showRename) {
            TextField("Snippet name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { store.rename(snippet.id, to: nameDraft) }
        }
    }
}
