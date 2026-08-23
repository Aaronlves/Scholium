import ScholiumContracts
import SwiftUI

/// A restrained, document-scoped Link and Fill surface. Search results and the
/// reviewed proposal are disposable; the Application owner separately commits
/// the portable relationship and absent managed Metadata fields.
struct ZoteroBindingPanelView: View {
    let route: ZoteroBindingPanelRoute
    let search: (String) async throws -> [ZoteroSearchHit]
    let prepareFill: (ZoteroSearchHit) async throws -> ZoteroMetadataFillPlan
    let commitFill: (ZoteroMetadataFillPlan) async throws -> Void
    let clearBinding: () async throws -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var hits: [ZoteroSearchHit] = []
    @State private var selectedID: ZoteroSearchHit.ID?
    @State private var fillPlan: ZoteroMetadataFillPlan?
    @State private var isSearching = false
    @State private var isPreparingFill = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            resultContent
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 500)
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
        .interactiveDismissDisabled(isSaving)
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
            "Could Not Link and Fill from Zotero",
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(currentBinding == nil ? "Link Zotero Item" : "Manage Zotero Link")
                    .font(ScholiumTypography.interface(.sectionTitle, emphasis: .strong))
                Text("Choose one exact item, then review the empty Scholium Metadata fields it can fill.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
            Spacer()
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
    }

    @ViewBuilder
    private var resultContent: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                            .font(.system(.caption, design: .monospaced))
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
        if selectedHit == nil {
            ScholiumApparatusStateView(
                "Select an Exact Item",
                detail: "The selected library and item key define the Zotero identity. Scholium will show every proposed Metadata change before enabling Link and Fill.",
                systemImage: "checkmark.circle",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        } else if isPreparingFill {
            ProgressView("Reading exact Zotero item and current Metadata…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let fillPlan {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.regionContentInset
                ) {
                    if fillPlan.fieldsToFill.isEmpty {
                        Text("No empty supported Metadata fields need filling.")
                            .font(ScholiumTypography.interface(.body))
                    } else {
                        metadataSection(
                            title: "Will Fill",
                            fields: fillPlan.fieldsToFill,
                            conflictPlan: nil
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
                detail: "Select the item again to reread Zotero and current Scholium Metadata.",
                systemImage: "exclamationmark.triangle",
                density: .block
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScholiumGrid.Spacing.regionContentInset)
        }
    }

    private func metadataSection(
        title: LocalizedStringKey,
        fields: [ZoteroMetadataFillField],
        conflictPlan: ZoteroMetadataFillPlan?
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fieldLabel(field.key))
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    if let conflictPlan,
                       let retained = conflictPlan.resultFields[field.key] {
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
        PropertyPresentationCatalog.presentation(for: key, in: .analysis)?.label
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

    private var footer: some View {
        HStack {
            if isSaving {
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
                .disabled(isSaving)
            Button(currentBinding == nil ? "Link and Fill" : "Rebind and Fill") {
                performSet()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(fillPlan == nil || isPreparingFill || isSaving)
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
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

    private func performSet() {
        guard let fillPlan, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await commitFill(fillPlan)
            } catch {
                errorMessage = error.localizedDescription
                await refreshFillPlan()
            }
        }
    }

    private func performClear() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await clearBinding()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
