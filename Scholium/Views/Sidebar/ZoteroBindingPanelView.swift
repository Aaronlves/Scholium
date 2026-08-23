import ScholiumContracts
import SwiftUI

/// Owns the panel-local save/clear task. WindowZoteroCoordinator owns the
/// underlying Zotero operation; this owner prevents a disappearing panel from
/// retrying, refreshing, or publishing presentation state after cancellation.
@MainActor
final class ZoteroBindingPanelMutationOwner: ObservableObject {
    @Published private(set) var isSaving = false

    private var generation: UInt64 = 0
    private var taskID: UUID?
    private var task: Task<Void, Never>?

    func perform(
        operation: @escaping @MainActor () async throws -> Void,
        didFail: @escaping @MainActor (Error) -> Void,
        recover: @escaping @MainActor () async -> Void = {}
    ) {
        guard task == nil else { return }
        generation &+= 1
        let operationGeneration = generation
        let operationID = UUID()
        isSaving = true
        taskID = operationID
        task = Task { @MainActor [weak self] in
            defer { self?.finish(operationID, generation: operationGeneration) }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self?.generation == operationGeneration else { return }
                didFail(error)
                await recover()
            }
        }
    }

    func cancelAll() {
        generation &+= 1
        task?.cancel()
        isSaving = false
    }

    func waitForIdle() async {
        _ = await task?.value
    }

    private func finish(_ operationID: UUID, generation operationGeneration: UInt64) {
        guard taskID == operationID else { return }
        taskID = nil
        task = nil
        if generation == operationGeneration {
            isSaving = false
        }
    }
}

/// A restrained, document-scoped Link and Fill surface. Search results and the
/// reviewed proposal are disposable; the Application owner separately commits
/// the portable relationship and absent managed Metadata fields.
struct ZoteroBindingPanelView: View {
    let route: ZoteroBindingPanelRoute
    let search: (String) async throws -> [ZoteroSearchHit]
    let prepareFill: (ZoteroSearchHit) async throws -> ZoteroMetadataPlan
    let prepareRefresh: () async throws -> ZoteroMetadataPlan
    let commitPlan: (ZoteroMetadataPlan) async throws -> Void
    let clearBinding: () async throws -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var hits: [ZoteroSearchHit] = []
    @State private var selectedID: ZoteroSearchHit.ID?
    @State private var fillPlan: ZoteroMetadataPlan?
    @State private var isSearching = false
    @State private var isPreparingFill = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @StateObject private var mutationOwner = ZoteroBindingPanelMutationOwner()

    var body: some View {
        routedPanel
        .interactiveDismissDisabled(mutationOwner.isSaving)
        .onDisappear {
            mutationOwner.cancelAll()
        }
        .confirmationDialog(
            "Clear Zotero Link?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear Link", role: .destructive) {
                performClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only Scholium’s portable relationship. It does not remove Metadata already filled in Scholium or change the Zotero item.")
        }
        .alert(
            errorTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            resultContent
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 500)
    }

    @ViewBuilder
    private var routedPanel: some View {
        switch route.mode {
        case .manage:
            panel
                .searchable(
                    text: $query,
                    placement: .toolbar,
                    prompt: "Zotero item key, title, author, or DOI"
                )
                .task(id: query) {
                    await refreshSearch()
                }
                .task(id: selectedID) {
                    await refreshFillPlan()
                }
        case .refresh:
            panel
                .task(id: route.id) {
                    await refreshBoundPlan()
                }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(headerTitle)
                    .font(ScholiumTypography.interface(.sectionTitle, emphasis: .strong))
                Text(headerDetail)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
            Spacer()
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
    }

    private var headerTitle: LocalizedStringKey {
        switch route.mode {
        case .manage:
            currentBinding == nil ? "Link Zotero Item" : "Manage Zotero Link"
        case .refresh:
            "Refresh Zotero Metadata"
        }
    }

    private var headerDetail: LocalizedStringKey {
        switch route.mode {
        case .manage:
            "Choose one exact item, then review the empty Scholium Metadata fields it can fill."
        case .refresh:
            "Read only the currently linked Zotero item, then review every Metadata field it can fill or update."
        }
    }

    private var errorTitle: LocalizedStringKey {
        route.mode == .refresh
            ? "Could Not Refresh Zotero Metadata"
            : "Could Not Link and Fill from Zotero"
    }

    @ViewBuilder
    private var resultContent: some View {
        if route.mode == .refresh {
            fillPreview
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScholiumApparatusStateView(
                "Search Zotero",
                detail: "Paste a Zotero item key for an exact lookup, or search by recognizable bibliographic metadata.",
                systemImage: "magnifyingglass",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        } else if isSearching {
            ProgressView("Searching Zotero…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hits.isEmpty {
            ScholiumApparatusStateView(
                "No Zotero Items Found",
                detail: "Try a title, author, DOI, ISBN, or citation key. Zotero must be open with its local API enabled.",
                systemImage: "books.vertical",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        } else {
            VStack(spacing: 0) {
                List(hits, selection: $selectedID) { hit in
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.labelAccessoryGap
                    ) {
                        if hit.item.title.isEmpty {
                            Text("Untitled Zotero Item")
                                .font(ScholiumTypography.scholarly(.emphasis))
                        } else {
                            Text(hit.item.title)
                                .font(ScholiumTypography.scholarly(.emphasis))
                        }
                        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            if !hit.item.formattedAuthors.isEmpty {
                                Text(hit.item.formattedAuthors)
                            }
                            if let year = hit.item.year {
                                Text(year.formatted())
                            }
                            Text(hit.library.name)
                        }
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        Text(hit.item.key)
                            .font(ScholiumTypography.exact(.small))
                            .scholiumForeground(.mutedText)
                            .accessibilityLabel("Zotero item key \(hit.item.key)")
                    }
                    .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                    .tag(hit.id)
                    .accessibilityElement(children: .combine)
                }
                .frame(minHeight: 170, idealHeight: 210, maxHeight: 250)
                .accessibilityIdentifier("scholium.zoteroBinding.results")
                Divider()
                fillPreview
            }
        }
    }

    @ViewBuilder
    private var fillPreview: some View {
        if route.mode == .manage, selectedHit == nil {
            ScholiumApparatusStateView(
                "Select an Exact Item",
                detail: "The selected library and item key define the Zotero identity. Scholium will show every proposed Metadata change before enabling Link and Fill.",
                systemImage: "checkmark.circle",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        } else if isPreparingFill
            || (route.mode == .refresh && fillPlan == nil && errorMessage == nil) {
            ProgressView("Reading exact Zotero item and current Metadata…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let fillPlan {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.regionContentInset
                ) {
                    if route.mode == .refresh {
                        refreshIdentity(plan: fillPlan)
                    }
                    if fillPlan.fieldsToFill.isEmpty {
                        if fillPlan.fieldsToUpdate.isEmpty {
                            Text("Zotero Metadata is current for every supported mapped field.")
                                .font(ScholiumTypography.interface(.body))
                        }
                    } else {
                        metadataSection(
                            title: "Will Fill",
                            fields: fillPlan.fieldsToFill,
                            conflictPlan: nil
                        )
                    }
                    if !fillPlan.fieldsToUpdate.isEmpty {
                        metadataSection(
                            title: "Will Update",
                            fields: fillPlan.fieldsToUpdate,
                            conflictPlan: fillPlan
                        )
                    }
                    if !fillPlan.retainedConflicts.isEmpty {
                        metadataSection(
                            title: "Existing Values Kept",
                            fields: fillPlan.retainedConflicts,
                            conflictPlan: fillPlan
                        )
                    }
                    Text("Zotero abstract, tags, citation key, collections, summary, keywords, and the Markdown body are not imported.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ScholiumGrid.Spacing.regionContentInset)
            }
            .accessibilityIdentifier("scholium.zoteroBinding.fillPreview")
        } else {
            ScholiumApparatusStateView(
                "Preview Unavailable",
                detail: String(localized: "Reload the Zotero Metadata preview to reread the exact item and current Scholium Metadata."),
                systemImage: "exclamationmark.triangle",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        }
    }

    private func refreshIdentity(plan: ZoteroMetadataPlan) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(plan.source.item.title.isEmpty
                ? String(localized: "Untitled Zotero Item")
                : plan.source.item.title)
                .font(ScholiumTypography.scholarly(.emphasis))
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(libraryLabel(plan.source.library))
                Text(plan.source.item.key)
                    .font(ScholiumTypography.exact(.small))
            }
            .font(ScholiumTypography.interface(.small))
            .scholiumForeground(.secondaryText)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.zoteroBinding.refreshIdentity")
    }

    private func libraryLabel(_ library: ZoteroLibraryMetadata) -> String {
        switch library.identity {
        case .user:
            String(localized: "My Library")
        case .group(let groupID):
            library.name == String(groupID)
                ? String(localized: "Zotero Group \(groupID)")
                : library.name
        }
    }

    private func metadataSection(
        title: LocalizedStringKey,
        fields: [ZoteroMetadataFillField],
        conflictPlan: ZoteroMetadataPlan?
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
            ForEach(fields) { field in
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.labelAccessoryGap
                ) {
                    Text(fieldLabel(field.key))
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    if let conflictPlan,
                       let retained = conflictPlan.originalFields[field.key] {
                        Text("Current: \(displayValue(retained, key: field.key))")
                        Text("Zotero: \(displayValue(field.value, key: field.key))")
                            .scholiumForeground(.secondaryText)
                    } else {
                        Text(displayValue(field.value, key: field.key))
                            .scholiumForeground(.secondaryText)
                    }
                }
                .font(ScholiumTypography.interface(.small))
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func fieldLabel(_ key: String) -> String {
        PropertyPresentationCatalog.presentation(
            for: key,
            in: .analysis,
            catalog: .builtIn
        )?.label
            ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func displayValue(_ value: YAMLValue, key: String) -> String {
        if key == "type", case .string(let rawValue) = value {
            return PropertyPresentationCatalog.choiceDisplayName(
                for: rawValue,
                fieldKey: key
            )
        }
        if let names = PropertyContractCatalog.creatorNames(from: value) {
            return names.map(\.displayName).joined(separator: ", ")
        }
        switch value {
        case .string(let value): return value
        case .integer(let value): return value.formatted()
        case .double(let value): return value.formatted()
        case .boolean(let value): return value ? "Yes" : "No"
        case .array(let values):
            return values.compactMap(\.scalarString).joined(separator: ", ")
        case .object: return "Structured value"
        case .null: return "Null"
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch route.mode {
        case .manage:
            HStack {
                if mutationOwner.isSaving {
                    ProgressView("Saving")
                        .controlSize(.small)
                } else if currentBinding != nil {
                    Button("Clear Link…", role: .destructive) {
                        confirmsClear = true
                    }
                }
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(mutationOwner.isSaving)
                Button(currentBinding == nil ? "Link and Fill" : "Rebind and Fill") {
                    performSet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fillPlan == nil || isPreparingFill || mutationOwner.isSaving)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
        case .refresh:
            HStack {
                if mutationOwner.isSaving {
                    ProgressView("Saving")
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(mutationOwner.isSaving)
                if let fillPlan {
                    if fillPlan.hasMetadataChanges {
                        Button("Refresh Metadata") {
                            performSet()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isPreparingFill || mutationOwner.isSaving)
                    } else {
                        Button("Done", action: dismiss)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
        }
    }

    private var selectedHit: ZoteroSearchHit? {
        guard let selectedID else { return nil }
        return hits.first { $0.id == selectedID }
    }

    private var currentBinding: AnalysisZoteroBinding? {
        fillPlan?.currentBinding ?? route.currentBinding
    }

    @MainActor
    private func refreshSearch() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            hits = []
            selectedID = nil
            fillPlan = nil
            isSearching = false
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let results = try await search(normalized)
            guard !Task.isCancelled,
                  normalized == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            hits = results
            if !results.contains(where: { $0.id == selectedID }) {
                selectedID = nil
                fillPlan = nil
            }
        } catch is CancellationError {
            return
        } catch {
            hits = []
            selectedID = nil
            fillPlan = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshFillPlan() async {
        guard let selectedHit else {
            fillPlan = nil
            isPreparingFill = false
            return
        }
        isPreparingFill = true
        fillPlan = nil
        defer { isPreparingFill = false }
        do {
            let plan = try await prepareFill(selectedHit)
            guard !Task.isCancelled, selectedID == selectedHit.id else { return }
            fillPlan = plan
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, selectedID == selectedHit.id else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshBoundPlan() async {
        isPreparingFill = true
        fillPlan = nil
        defer { isPreparingFill = false }
        do {
            let plan = try await prepareRefresh()
            guard !Task.isCancelled else { return }
            fillPlan = plan
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func performSet() {
        guard let fillPlan, !mutationOwner.isSaving else { return }
        mutationOwner.perform(
            operation: {
                try await commitPlan(fillPlan)
            },
            didFail: { error in
                errorMessage = error.localizedDescription
            },
            recover: {
                switch route.mode {
                case .manage:
                    await refreshFillPlan()
                case .refresh:
                    await refreshBoundPlan()
                }
            }
        )
    }

    private func performClear() {
        guard !mutationOwner.isSaving else { return }
        mutationOwner.perform(
            operation: {
                try await clearBinding()
            },
            didFail: { error in
                errorMessage = error.localizedDescription
            }
        )
    }
}
