import ScholiumContracts
import SwiftUI

/// A restrained, document-scoped picker for the portable Zotero relationship.
/// Search results are disposable Zotero metadata; only the selected stable
/// library identity and item key are written by the caller.
struct ZoteroBindingPanelView: View {
    let route: ZoteroBindingPanelRoute
    let search: (String) async throws -> [ZoteroSearchHit]
    let setBinding: (ZoteroSearchHit) async throws -> Void
    let clearBinding: () async throws -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var hits: [ZoteroSearchHit] = []
    @State private var selectedID: ZoteroSearchHit.ID?
    @State private var isSearching = false
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
            prompt: "Title, author, DOI, or citation key"
        )
        .task(id: query) {
            await refreshSearch()
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
            Text("This removes only Scholium’s portable relationship. It does not change the Analysis note or the Zotero item.")
        }
        .alert(
            "Could Not Update Zotero Link",
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
                Text(route.currentBinding == nil ? "Link Zotero Item" : "Manage Zotero Link")
                    .font(ScholiumTypography.interface(.sectionTitle, emphasis: .strong))
                Text("Choose one exact item from a local Zotero library.")
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
                detail: "Search by a stable bibliographic identifier or recognizable metadata, then verify the exact library before linking.",
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
            List(hits, selection: $selectedID) { hit in
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.labelAccessoryGap
                ) {
                    Text(hit.item.title)
                        .font(ScholiumTypography.scholarly(.emphasis))
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
                }
                .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                .tag(hit.id)
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("scholium.zoteroBinding.results")
        }
    }

    private var footer: some View {
        HStack {
            if route.currentBinding != nil {
                Button("Clear Link…", role: .destructive) {
                    confirmsClear = true
                }
                .disabled(isSaving)
            }
            Spacer()
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
            Button(route.currentBinding == nil ? "Link" : "Rebind") {
                performSet()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedHit == nil || isSaving)
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
    }

    private var selectedHit: ZoteroSearchHit? {
        guard let selectedID else { return nil }
        return hits.first { $0.id == selectedID }
    }

    @MainActor
    private func refreshSearch() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            hits = []
            selectedID = nil
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
            }
        } catch is CancellationError {
            return
        } catch {
            hits = []
            selectedID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func performSet() {
        guard let selectedHit, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await setBinding(selectedHit)
            } catch {
                errorMessage = error.localizedDescription
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
