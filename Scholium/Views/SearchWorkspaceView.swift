import ScholiumCore
import SwiftUI

struct SearchWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var showSaveSearch = false
    @State private var savedSearchName = ""
    @State private var renamingSearch: SavedSearch?
    @State private var renamedSearchName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Search", systemImage: "magnifyingglass")
                    .font(.headline)
                TextField("Search notes and metadata", text: query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityIdentifier("scholium.searchField")
                    .accessibilityLabel("Search")
                    .onSubmit { Task { await appState.refreshAdvancedSearch() } }
                Picker("Search mode", selection: scope) {
                    Text("Triptych").tag(SearchPresentationScope.triptych)
                    Text("This Note").tag(SearchPresentationScope.thisNote)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .accessibilityIdentifier("scholium.searchMode")
                Menu {
                    Button("Save Current Search…") {
                        savedSearchName = appState.advancedSearchState.query
                        showSaveSearch = true
                    }
                    .disabled(appState.advancedSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !appState.savedSearches.isEmpty {
                        Divider()
                        ForEach(Array(appState.savedSearches.enumerated()), id: \.element.id) { index, search in
                            Menu(search.name) {
                                Button("Run Search") { appState.runSavedSearch(search) }
                                Button("Rename…") {
                                    renamedSearchName = search.name
                                    renamingSearch = search
                                }
                                Divider()
                                Button("Move Up") { appState.moveSavedSearch(search.id, by: -1) }
                                    .disabled(index == 0)
                                Button("Move Down") { appState.moveSavedSearch(search.id, by: 1) }
                                    .disabled(index == appState.savedSearches.count - 1)
                                Divider()
                                Button("Delete", role: .destructive) {
                                    appState.deleteSavedSearch(search.id)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Saved Searches", systemImage: "bookmark")
                }
                Button("Close") { appState.showSearchSurface = false }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            if let searchError = appState.advancedSearchError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Search Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                    Text(searchError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Retry") { Task { await appState.refreshAdvancedSearch() } }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.10))
                .accessibilityElement(children: .combine)
                Divider()
            }

            Divider()

            if appState.isSearchRunning {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.advancedSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Search Your Workspace",
                    systemImage: "text.magnifyingglass",
                    description: Text("Search the active Triptych or limit results to the current note. Use phrases, exclusions, and fields such as author:, tag:, role:, status:, review:, and has:broken-link.")
                )
            } else if appState.advancedSearchHits.isEmpty {
                ContentUnavailableView.search(text: appState.advancedSearchState.query)
            } else {
                results
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.searchWorkspace")
        .onAppear { searchFocused = true }
        .onDisappear { searchTask?.cancel() }
        .alert("Save Search", isPresented: $showSaveSearch) {
            TextField("Search name", text: $savedSearchName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { appState.saveCurrentSearch(named: savedSearchName) }
        } message: {
            Text("Saved searches remain in Scholium’s Application Support folder and never modify a vault.")
        }
        .alert("Rename Saved Search", isPresented: Binding(
            get: { renamingSearch != nil },
            set: { if !$0 { renamingSearch = nil } }
        )) {
            TextField("Search name", text: $renamedSearchName)
            Button("Cancel", role: .cancel) { renamingSearch = nil }
            Button("Rename") {
                if let renamingSearch {
                    appState.renameSavedSearch(renamingSearch.id, to: renamedSearchName)
                }
                renamingSearch = nil
            }
            .disabled(renamedSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var query: Binding<String> {
        Binding(
            get: { appState.advancedSearchState.query },
            set: { value in
                appState.advancedSearchState.query = value
                scheduleSearch()
            }
        )
    }

    private var scope: Binding<SearchPresentationScope> {
        Binding(
            get: { appState.advancedSearchState.scope },
            set: { value in
                appState.advancedSearchState.scope = value
                scheduleSearch(immediate: true)
            }
        )
    }

    private var results: some View {
        List(appState.advancedSearchHits, id: \.self) { hit in
            Button {
                appState.openSearchHit(hit)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(hit.title).font(.headline).lineLimit(1)
                        Spacer()
                        Text(hit.vaultName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(hit.snippet)
                        .font(.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(hit.matchedField.rawValue.capitalized)
                        Text("Line \(hit.sourceLine)")
                        Text(Self.triptychLabel(for: hit.vaultRole))
                        Text("Retrieval lead")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(hit.title), \(hit.vaultName), line \(hit.sourceLine)")
            .accessibilityIdentifier("scholium.searchResult.\(hit.relativePath)")
        }
    }

    private static let triptychRoles: [(roles: Set<VaultRole>, label: String)] = [
        ([.sourceCorpus], "Analyses"),
        ([.topicKnowledge], "Topics"),
        ([.dissertationControl, .draftProject], "Works"),
    ]

    private static func triptychLabel(for role: VaultRole) -> String {
        triptychRoles.first(where: { $0.roles.contains(role) })?.label ?? "Unclassified"
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            await appState.refreshAdvancedSearch()
        }
    }
}
