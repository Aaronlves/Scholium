import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct ZoteroSettingsView: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var info = ZoteroLibraryInfo(
        status: .appUnavailable, lastSuccessfulConnection: nil)
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Zotero Desktop") {
            LabeledContent("Local API") {
                Label(statusTitle, systemImage: statusSymbol)
                    .foregroundStyle(.primary)
            }
            LabeledContent("Last Connected") {
                Text(
                    info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened)
                        ?? localizedInterfaceString("Never")
                )
                .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    zoteroActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    zoteroActions
                }
            }
            Text(
                "Scholium uses Zotero Desktop's localhost API, not its private database. Chat item changes require confirmation and Zotero's local write authorization. Import BibTeX and RIS in Zotero."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if info.status == .apiDisabled {
                Text(
                    "In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            let current = await settingsModel.zoteroConnectionInfo()
            guard !Task.isCancelled else { return }
            info = current
        }
        .accessibilityIdentifier("scholium.settings.zotero.connection")
    }

    @ViewBuilder
    private var zoteroActions: some View {
        Button("Open Zotero") {
            Task { await settingsModel.openZotero() }
        }
        Button("Check Connection") { refresh() }
            .disabled(isTesting)
        Button("Clear History", role: .destructive) {
            Task {
                try? await settingsModel.clearZoteroConnectionHistory()
                info = await settingsModel.zoteroConnectionInfo()
            }
        }
        .accessibilityLabel("Clear Connection History")
    }

    private var statusTitle: String {
        switch info.status {
        case .available, .itemMissing:
            localizedInterfaceString("Connected")
        case .apiDisabled:
            localizedInterfaceString("Access Disabled in Zotero")
        case .appUnavailable:
            localizedInterfaceString("Zotero Not Available")
        }
    }

    private var statusSymbol: String {
        info.status == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func refresh() {
        isTesting = true
        Task {
            do {
                info = try await settingsModel.refreshZoteroLibraryInfo()
                errorMessage = nil
            } catch {
                info = await settingsModel.zoteroConnectionInfo()
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}

struct ZoteroOriginalAccessSettingsView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var grants: [ZoteroOriginalAccessGrant] = []
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var isFindingLibrary = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?
    @State private var loadGeneration = 0

    var body: some View {
        Section {
            originalText(
                "Scholium locates your Zotero library folder. Confirm Allow Read Access in the file picker. Access is read-only, limited to Zotero originals, and saved on this Mac."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if isLoading {
                ProgressView { originalText("Loading Original Access…") }
            } else if grants.isEmpty, errorMessage == nil {
                originalText("No original files or folders selected.")
                    .foregroundStyle(.secondary)
            }
            if isFindingLibrary {
                HStack {
                    ProgressView { originalText("Finding Zotero Library Folder…") }
                    Button {
                        operation?.cancel()
                    } label: {
                        originalText("Cancel")
                    }
                }
            }
            ForEach(grants) { grant in
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Label(
                        URL(fileURLWithPath: grant.path).lastPathComponent,
                        systemImage: grant.kind == .folder ? "folder" : "doc"
                    )
                    Text(grant.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(
                        grant.status == .available ? originalString("Read Access Available") : originalString("Original Access Required"),
                        systemImage: grant.status == .available ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .font(.callout)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) { grantActions(grant) }
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) { grantActions(grant) }
                    }
                    .disabled(isUpdating)
                }
                .accessibilityElement(children: .contain)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) { addActions }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) { addActions }
            }
            .disabled(isUpdating)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: reload) { originalText("Reload Original Access") }
                .disabled(isUpdating)
        } header: {
            HStack {
                originalText("Original File Access")
                Spacer()
                originalText("This Mac").foregroundStyle(.secondary)
            }
        }
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            await loadGrants()
        }
        .onChange(of: isPaneActive) { _, active in
            if !active { operation?.cancel() }
        }
        .onDisappear { operation?.cancel() }
        .accessibilityIdentifier("scholium.settings.zotero.originalAccess")
    }

    @ViewBuilder
    private var addActions: some View {
        Button {
            select(kind: .folder)
        } label: {
            originalText("Choose Zotero Library Folder…")
        }
        .accessibilityIdentifier("scholium.settings.zotero.originalAccess.addFolder")
        Button {
            select(kind: .file)
        } label: {
            originalText("Add Original File…")
        }
        .accessibilityIdentifier("scholium.settings.zotero.originalAccess.addFile")
    }

    @ViewBuilder
    private func grantActions(_ grant: ZoteroOriginalAccessGrant) -> some View {
        Button {
            select(kind: grant.kind, replacing: grant)
        } label: {
            originalText("Restore Original Access…")
        }
        .accessibilityLabel(originalText("Restore Original Access for \(grant.path)"))
        Button(role: .destructive) {
            isUpdating = true
            operation = Task {
                defer { isUpdating = false }
                do {
                    try await settingsModel.removeZoteroOriginalAccess(grantID: grant.id)
                    await loadGrants()
                } catch { errorMessage = accessErrorMessage(error) }
            }
        } label: {
            originalText("Remove Original Access")
        }
        .accessibilityLabel(originalText("Remove Original Access for \(grant.path)"))
    }

    private func select(kind: ZoteroOriginalAccessGrant.Kind, replacing grant: ZoteroOriginalAccessGrant? = nil) {
        isUpdating = true
        operation = Task {
            defer {
                isUpdating = false
                isFindingLibrary = false
            }
            do {
                errorMessage = nil
                var directory: URL?
                if grant == nil, kind == .folder {
                    isFindingLibrary = true
                    directory = try? await settingsModel.suggestedZoteroOriginalLibraryDirectory()
                    isFindingLibrary = false
                }
                try Task.checkCancellation()
                let request = Self.selectionRequest(kind: kind, grant: grant, locatedLibraryURL: directory, locale: locale)
                guard let selected = try await fileSelectionPresenter.requiredForFileSelection().selectURL(request) else { return }
                try Task.checkCancellation()
                try await settingsModel.authorizeZoteroOriginalAccess(selectedURL: selected, replacing: grant?.id)
                await loadGrants()
            } catch is CancellationError {
                // Cancelling the native picker retains the existing grants.
            } catch { errorMessage = accessErrorMessage(error) }
        }
    }

    static func selectionRequest(
        kind: ZoteroOriginalAccessGrant.Kind,
        grant: ZoteroOriginalAccessGrant? = nil,
        locatedLibraryURL: URL? = nil,
        locale: Locale
    ) -> ScholiumFileSelectionRequest {
        func text(_ key: String.LocalizationValue) -> String { ScholiumL10n.string(key, locale: locale) }
        let selectedRoot = grant.map { URL(fileURLWithPath: $0.path) }
        let message: String.LocalizationValue
        if grant != nil {
            message = "Select the same file or folder to restore read-only access."
        } else if kind == .file {
            message = "Select an original file to allow read-only access."
        } else if locatedLibraryURL != nil {
            message = "Zotero identified this library folder. Confirm Allow Read Access to read its originals."
        } else {
            message =
                "Scholium could not locate the library folder. Choose it manually using Show Data Directory in Zotero Settings → Advanced → Files and Folders."
        }
        return ScholiumFileSelectionRequest(
            title: text(grant == nil && kind == .folder ? "Choose Zotero Library Folder…" : "Original File Access"),
            message: text(message), prompt: text("Allow Read Access"),
            initialDirectoryURL: selectedRoot?.deletingLastPathComponent() ?? (kind == .folder ? locatedLibraryURL : nil),
            kind: kind == .folder ? .directory(canCreateDirectories: false) : .files(allowedContentTypes: [.item], resolvesAliases: false)
        )
    }

    private func reload() {
        operation = Task { await loadGrants() }
    }

    private func loadGrants() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let current = try await settingsModel.zoteroOriginalAccessGrants()
            guard !Task.isCancelled, generation == loadGeneration else { return }
            grants = current
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            errorMessage = accessErrorMessage(error)
        }
    }

    private func accessErrorMessage(_ error: any Error) -> String {
        guard let accessError = error as? ZoteroOriginalAccessError else { return error.localizedDescription }
        let resource: LocalizedStringResource =
            switch accessError {
            case .storageUnavailable:
                LocalizedStringResource(
                    "Original access settings are unavailable. Reopen Scholium and try again.", table: "Interface", locale: locale, bundle: .module)
            case .damagedConfiguration:
                LocalizedStringResource(
                    "Original access settings cannot be read. Existing settings were preserved.", table: "Interface", locale: locale, bundle: .module)
            case .invalidSelection:
                LocalizedStringResource(
                    "Select an original file or its folder directly. Symbolic links are not supported.", table: "Interface", locale: locale, bundle: .module)
            case .grantMissing:
                LocalizedStringResource(
                    "This original access grant was removed. Reload the list and try again.", table: "Interface", locale: locale, bundle: .module)
            }
        return String(localized: resource)
    }

    private func originalText(_ value: String.LocalizationValue) -> Text {
        Text(LocalizedStringResource(value, table: "Localizable", locale: locale, bundle: .module))
    }

    private func originalString(_ value: String.LocalizationValue) -> String {
        ScholiumL10n.string(value, locale: locale)
    }
}
