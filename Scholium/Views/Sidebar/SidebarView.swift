import SwiftUI
import ScholiumCore

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var expandedFolders: Set<String> = []
    @State private var lifecycleOverlayScope: AppState.NoteLocationScope?
    @State private var workspaceFolderSnapshot: [TreeNode] = []
    @State private var showUnclassified = false
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

    private var visibleAttentionCount: Int? {
        guard let items = appState.workspaceCatalog?.attention else { return nil }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(items).count
    }

    /// Notes filtered within the selected Triptych vault and location scope.
    private var filteredNotes: [Note] {
        appState.filteredNotes
    }

    /// Build folder tree from filtered notes
    private var folderTree: [TreeNode] {
        buildTree(from: filteredNotes, notesAreOrdered: appState.notesAreOrdered)
    }

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 9)

            workspaceVaultPicker
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Button {
                appState.showAttentionQueues = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(.secondary)
                    Text("Attention")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if let count = visibleAttentionCount {
                        Text(count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.tint(.yellow.opacity(0.14)).interactive(),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
            .help("Review derived warnings and recoverable research issues")

            Divider().opacity(0.15)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    libraryHeader

                    filtersSection

                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedFolderTree) { node in
                                TreeNodeView(
                                    node: node,
                                    expandedFolders: $expandedFolders,
                                    activeTab: appState.activeTab,
                                    onSelect: { appState.requestOpenNote($0) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollContentBackground(.hidden)
                }
                .opacity(lifecycleOverlayScope == nil ? 1 : 0.48)
                .allowsHitTesting(lifecycleOverlayScope == nil)

                if let scope = lifecycleOverlayScope {
                    SidebarLifecycleCard(
                        scope: scope,
                        notes: appState.noteLocationScope == scope ? appState.notes : [],
                        isLoading: appState.noteLocationScope != scope,
                        onClose: closeLifecycleOverlay
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()
                .opacity(0.5)

            unclassifiedNavigation

            Divider()
                .padding(.horizontal, 12)

            lifecycleNavigation
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityIdentifier("scholium.sidebar")
        .onAppear { captureWorkspaceSnapshotIfNeeded() }
        .onChange(of: appState.notes.map(\.relativePath)) { _, _ in
            captureWorkspaceSnapshotIfNeeded()
        }
        .sheet(isPresented: $showUnclassified, onDismiss: restoreWorkspaceAfterTransientScope) {
            UnclassifiedClassificationSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - Header and Search

    private var brandHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scholium")
                    .font(.title3.weight(.semibold))
                Text("Triptych — \(appState.workspaceAssignment?.triptych.name ?? "Not Selected")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    openSettings()
                } label: {
                    Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
                }
                Button {
                    appState.revealVaultInFinder()
                } label: {
                    Label("Reveal Current Vault in Finder", systemImage: "folder")
                }
                .disabled(appState.vaultConfig == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel("Triptych options")
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Button {
                appState.requestNoteLocationScope(.workspace)
            } label: {
                Label("Library", systemImage: "books.vertical")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(appState.noteLocationScope == .workspace ? .isSelected : [])

            Spacer()

            Text("\(appState.filteredNotes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                appState.noteLifecycleRequest = .create
            } label: {
                Label("New Note", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("New Note")
            .accessibilityIdentifier("scholium.newNote")
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
    }

    private var unclassifiedNavigation: some View {
        Button {
            captureWorkspaceSnapshotIfNeeded()
            showUnclassified = true
            appState.requestNoteLocationScope(.unclassified)
        } label: {
            Label("Unclassified", systemImage: "tray.and.arrow.down")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .help("Classify imported Markdown")
        .accessibilityIdentifier("scholium.location.unclassified")
    }

    private var lifecycleNavigation: some View {
        VStack(spacing: 1) {
            locationButton(.setAside, symbol: "archivebox")
            locationButton(.trash, symbol: "trash")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func locationButton(_ scope: AppState.NoteLocationScope, symbol: String) -> some View {
        Button {
            openLifecycleOverlay(scope)
        } label: {
            Label(scope.rawValue, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            lifecycleOverlayScope == scope ? .regular.interactive() : .identity,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityAddTraits(lifecycleOverlayScope == scope ? .isSelected : [])
        .accessibilityIdentifier(
            scope == .setAside ? "scholium.location.setAside" : "scholium.location.trash"
        )
    }

    private var displayedFolderTree: [TreeNode] {
        if lifecycleOverlayScope != nil, !workspaceFolderSnapshot.isEmpty {
            return workspaceFolderSnapshot
        }
        return folderTree
    }

    private func captureWorkspaceSnapshotIfNeeded() {
        guard appState.noteLocationScope == .workspace else { return }
        workspaceFolderSnapshot = folderTree
    }

    private func openLifecycleOverlay(_ scope: AppState.NoteLocationScope) {
        guard scope == .setAside || scope == .trash else { return }
        if lifecycleOverlayScope == scope {
            closeLifecycleOverlay()
            return
        }
        captureWorkspaceSnapshotIfNeeded()
        lifecycleOverlayScope = scope
        appState.requestNoteLocationScope(scope)
    }

    private func closeLifecycleOverlay() {
        lifecycleOverlayScope = nil
        restoreWorkspaceAfterTransientScope()
    }

    private func restoreWorkspaceAfterTransientScope() {
        appState.requestNoteLocationScope(.workspace)
    }

    // MARK: - Knowledge Base Picker

    private var workspaceVaultPicker: some View {
        Picker("Triptych", selection: currentWorkspaceSlotBinding) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Text(slot.displayName).tag(slot)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .accessibilityLabel("Triptych vault")
    }

    private var currentWorkspaceSlotBinding: Binding<WorkspaceVaultSlot> {
        Binding(
            get: { currentWorkspaceSlot ?? .paperAnalysis },
            set: { slot in
                guard !isCurrent(slot) else { return }
                appState.requestWorkspaceVault(slot)
            }
        )
    }

    private func isCurrent(_ slot: WorkspaceVaultSlot) -> Bool {
        guard let assigned = appState.workspaceAssignment?.vault(for: slot),
              let current = appState.currentRegisteredVault else { return false }
        return current.id == assigned.id || current.canonicalPath == assigned.canonicalPath
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first(where: isCurrent)
    }

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if appState.currentVaultRole.allowsHumanReview {
                    Toggle(isOn: $appState.isReviewedFilter) {
                        Text("Unreviewed")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }

                Spacer()

                Text("\(appState.filteredNotes.count) notes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if appState.currentVaultRole.allowsHumanReview,
               appState.humanReviewRecords.values.contains(where: {
                   $0.latestReview?.qualification == .unqualified
               }) {
                Toggle(isOn: $appState.isUnqualifiedFilter) {
                    Label("Unqualified", systemImage: "xmark.seal")
                        .font(.caption)
                        .foregroundStyle(appState.isUnqualifiedFilter ? .red : .primary)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: 12) {
                Menu {
                    Button {
                        appState.selectedTag = nil
                    } label: {
                        if appState.selectedTag == nil {
                            Label("All Tags", systemImage: "checkmark")
                        } else {
                            Text("All Tags")
                        }
                    }
                    Divider()
                    ForEach(appState.allTags, id: \.self) { tag in
                        Button {
                            appState.selectedTag = tag
                        } label: {
                            if appState.selectedTag == tag {
                                Label(tag, systemImage: "checkmark")
                            } else {
                                Text(tag)
                            }
                        }
                    }
                } label: {
                    Image(systemName: appState.selectedTag == nil ? "tag" : "tag.fill")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(appState.allTags.isEmpty)
                .help(appState.selectedTag.map { "Tag: \($0)" } ?? "Filter by tag")
                .accessibilityLabel("Tag filter")
                .accessibilityValue(appState.selectedTag ?? "All tags")

            Menu {
                Menu("Status") {
                    Button("Any Status") { appState.selectedStatus = nil }
                    Divider()
                    ForEach(appState.availableStatuses, id: \.self) { status in
                        Button {
                            appState.selectedStatus = status
                        } label: {
                            if appState.selectedStatus == status {
                                Label(status.capitalized, systemImage: "checkmark")
                            } else {
                                Text(status.capitalized)
                            }
                        }
                    }
                }

                if !appState.availableAuthors.isEmpty {
                    Menu("Author") {
                        Button("Any Author") { appState.selectedAuthor = nil }
                        Divider()
                        ForEach(appState.availableAuthors, id: \.self) { author in
                            Button {
                                appState.selectedAuthor = author
                            } label: {
                                if appState.selectedAuthor == author {
                                    Label(author, systemImage: "checkmark")
                                } else {
                                    Text(author)
                                }
                            }
                        }
                    }
                }

                if !appState.availableYears.isEmpty {
                    Menu("Year") {
                        Button("Any Year") { appState.selectedYear = nil }
                        Divider()
                        ForEach(appState.availableYears, id: \.self) { year in
                            Button {
                                appState.selectedYear = year
                            } label: {
                                if appState.selectedYear == year {
                                    Label(year.formatted(.number.grouping(.never)), systemImage: "checkmark")
                                } else {
                                    Text(year.formatted(.number.grouping(.never)))
                                }
                            }
                        }
                    }
                }

                if !appState.availablePropertyKeys.isEmpty {
                    Menu("Property") {
                        Button("Any Property") {
                            appState.selectedPropertyKey = nil
                            appState.selectedPropertyValue = nil
                        }
                        Divider()
                        ForEach(appState.availablePropertyKeys, id: \.self) { key in
                            Menu(propertyLabel(key)) {
                                ForEach(appState.availablePropertyValues(for: key), id: \.self) { value in
                                    Button {
                                        appState.selectedPropertyKey = key
                                        appState.selectedPropertyValue = value
                                    } label: {
                                        if appState.selectedPropertyKey == key,
                                           appState.selectedPropertyValue == value {
                                            Label(value, systemImage: "checkmark")
                                        } else {
                                            Text(value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if appState.activeMetadataFilterCount > 0 {
                    Divider()
                    Button("Clear Metadata Filters") { appState.clearMetadataFilters() }
                }
            } label: {
                Image(systemName: appState.activeMetadataFilterCount == 0
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(appState.activeMetadataFilterCount == 0
                ? "Filter by metadata"
                : "\(appState.activeMetadataFilterCount) metadata filters active")
            .accessibilityLabel("Metadata filters")
            .accessibilityValue("\(appState.activeMetadataFilterCount) active")

            Menu {
                ForEach(AppState.NoteSortOrder.allCases) { order in
                    Button {
                        appState.noteSortOrder = order
                    } label: {
                        if appState.noteSortOrder == order {
                            Label(order.title, systemImage: "checkmark")
                        } else {
                            Text(order.title)
                        }
                    }
                }
            } label: {
                Image(systemName: appState.noteSortOrder.symbol)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Sort: \(appState.noteSortOrder.title)")
            .accessibilityLabel("Sort notes")
            .accessibilityValue(appState.noteSortOrder.title)

                Spacer(minLength: 0)
            }

            if !appState.changedSinceReviewPaths.isEmpty {
                Label("\(appState.changedSinceReviewPaths.count) changed since review", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func propertyLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct SidebarLifecycleCard: View {
    @EnvironmentObject private var appState: AppState

    let scope: AppState.NoteLocationScope
    let notes: [Note]
    let isLoading: Bool
    let onClose: () -> Void

    @State private var pendingPermanentDeletion: Note?

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onClose) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 34, height: 4)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse \(scope.rawValue)")
            .accessibilityLabel("Collapse \(scope.rawValue)")

            HStack {
                Text(scope.rawValue)
                    .font(.callout.weight(.semibold))
                Spacer()
                if !isLoading {
                    Text(notes.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                ProgressView("Opening \(scope.rawValue)…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if notes.isEmpty {
                ContentUnavailableView(
                    scope.rawValue,
                    systemImage: scope == .trash ? "trash" : "archivebox",
                    description: Text("No notes are currently in \(scope.rawValue).")
                )
                .frame(minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { note in
                            Button {
                                appState.requestOpenNote(note.relativePath)
                            } label: {
                                Text(note.title ?? note.displayName)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    appState.noteLifecycleRequest = .restore(note.relativePath)
                                } label: {
                                    Label("Restore…", systemImage: "arrow.uturn.backward")
                                }
                                if scope == .setAside {
                                    Button {
                                        moveToTrash(note)
                                    } label: {
                                        Label("Move to Trash…", systemImage: "trash")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        pendingPermanentDeletion = note
                                    } label: {
                                        Label("Delete Permanently…", systemImage: "trash.slash")
                                    }
                                }
                                Divider()
                                Button {
                                    appState.showInFinder(note.relativePath)
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                            }
                            .accessibilityLabel(note.title ?? note.displayName)
                            .accessibilityHint("Open note in \(scope.rawValue)")

                            if note.id != notes.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 170, idealHeight: 280, maxHeight: 360)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            scope == .setAside ? "scholium.lifecycleCard.setAside" : "scholium.lifecycleCard.trash"
        )
        .confirmationDialog(
            "Delete Permanently?",
            isPresented: Binding(
                get: { pendingPermanentDeletion != nil },
                set: { if !$0 { pendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let note = pendingPermanentDeletion {
                Button("Delete Permanently", role: .destructive) {
                    deletePermanently(note)
                }
            }
            Button("Cancel", role: .cancel) { pendingPermanentDeletion = nil }
        } message: {
            Text("This cannot be undone. Scholium removes the note, its Review and comments, Dialogue records, Critique association, stable identity, Note History, and every Triptych checkpoint containing it.")
        }
    }

    private func moveToTrash(_ note: Note) {
        Task {
            do {
                try await appState.moveNoteToTrash(note.relativePath)
            } catch {
                appState.showToast("Could not move this note to Trash. \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func deletePermanently(_ note: Note) {
        pendingPermanentDeletion = nil
        Task {
            do {
                try await appState.deleteNotePermanently(note.relativePath)
            } catch {
                appState.showToast("Could not permanently delete this note. \(error.localizedDescription)", kind: .error)
            }
        }
    }
}

private struct UnclassifiedClassificationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unclassified")
                        .font(.title2.weight(.semibold))
                    Text("Choose a Triptych destination for each imported note.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            if appState.noteLocationScope != .unclassified {
                ProgressView("Opening Unclassified…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.notes.isEmpty {
                ContentUnavailableView(
                    "No Unclassified Notes",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Imported Markdown appears here until you choose Analyses, Topics, or Works.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.notes) { note in
                            UnclassifiedClassificationRow(note: note)
                            if note.id != appState.notes.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 300, idealHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.unclassifiedPanel")
    }
}

private struct UnclassifiedClassificationRow: View {
    @EnvironmentObject private var appState: AppState

    let note: Note

    @State private var destinationSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var isClassifying = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title ?? note.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(note.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Destination", selection: $destinationSlot) {
                ForEach(WorkspaceVaultSlot.allCases) { slot in
                    Text(slot.displayName).tag(slot)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Button("Classify") { classify() }
                .buttonStyle(.glass)
                .disabled(isClassifying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func classify() {
        isClassifying = true
        Task {
            do {
                try await appState.classifyUnclassified(
                    note.relativePath,
                    into: destinationSlot,
                    destination: note.relativePath
                )
            } catch {
                isClassifying = false
                appState.showToast("Could not classify this note. \(error.localizedDescription)", kind: .error)
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Line \(result.sourceLine)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(highlightedSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(result.matchField.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.displayName), match on line \(result.sourceLine)")
        .accessibilityHint("Open the exact source line")
    }

    private var highlightedSnippet: AttributedString {
        var attributed = AttributedString(result.snippet)
        let ns = result.snippet as NSString
        for highlight in result.highlights {
            let range = NSRange(
                location: highlight.utf16LowerBound,
                length: highlight.utf16UpperBound - highlight.utf16LowerBound
            )
            guard range.location >= 0, NSMaxRange(range) <= ns.length,
                  let stringRange = Range(range, in: result.snippet),
                  let attributedRange = Range(stringRange, in: attributed) else { continue }
            attributed[attributedRange].backgroundColor = .accentColor.opacity(0.18)
            attributed[attributedRange].foregroundColor = .primary
        }
        return attributed
    }
}

// MARK: - Tree Node Model

struct TreeNode: Identifiable {
    let id: String       // full path
    let name: String     // display name
    let isFolder: Bool
    let note: Note?      // nil for folders
    let children: [TreeNode]
    let depth: Int
}

/// Build a folder tree from flat note list
func buildTree(
    from notes: [Note],
    notesAreOrdered: (Note, Note) -> Bool
) -> [TreeNode] {
    var roots: [TreeNode] = []
    var folderMap: [String: [Note]] = [:]

    for note in notes {
        // Strip KB root prefix (e.g., "papers/", "topics/", "output/")
        let stripped = stripKBRoot(note.relativePath)
        let parts = stripped.split(separator: "/").map(String.init)
        if parts.count == 0 || (parts.count == 1 && parts[0].isEmpty) {
            roots.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: 0))
        } else if parts.count == 1 {
            roots.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: 0))
        } else {
            let folderPath = parts.dropLast().joined(separator: "/")
            folderMap[folderPath, default: []].append(note)
        }
    }

    // Build folder nodes
    func buildNode(path: String, depth: Int) -> TreeNode {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        var children: [TreeNode] = []

        // Add files directly in this folder
        if let files = folderMap[path] {
            for note in files {
                children.append(TreeNode(id: note.relativePath, name: note.displayName, isFolder: false, note: note, children: [], depth: depth + 1))
            }
        }

        // Add subfolders
        let prefix = path + "/"
        let subfolders = Set(folderMap.keys.filter { $0.hasPrefix(prefix) && $0 != path }.map { $0.split(separator: "/").prefix(depth + 2).joined(separator: "/") })
        for sub in subfolders.sorted() {
            children.append(buildNode(path: sub, depth: depth + 1))
        }

        return TreeNode(id: path, name: name, isFolder: true, note: nil, children: children.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            if let left = a.note, let right = b.note { return notesAreOrdered(left, right) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }, depth: depth)
    }

    // Collect top-level folders
    let topFolders = Set(folderMap.keys.map { $0.split(separator: "/").first.map(String.init) ?? $0 })
    for folder in topFolders.sorted() {
        if !roots.contains(where: { $0.id == folder }) {
            roots.append(buildNode(path: folder, depth: 0))
        }
    }

    return roots.sorted { a, b in
        if a.isFolder != b.isFolder { return a.isFolder }
        if let left = a.note, let right = b.note { return notesAreOrdered(left, right) }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// Strip the KB root prefix from a path (e.g., "papers/ethics/note.md" → "ethics/note.md")
func stripKBRoot(_ path: String) -> String {
    let kbPrefixes = ["papers/", "topics/", "output/"]
    for prefix in kbPrefixes {
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
    }
    return path
}

// MARK: - Tree Node View

struct TreeNodeView: View {
    @EnvironmentObject var appState: AppState
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let activeTab: String?
    let onSelect: (String) -> Void

    @State private var pendingDestructiveAction: DestructiveAction?

    private enum DestructiveAction: String, Identifiable {
        case setAside = "Set Aside"
        case trash = "Move to Trash"
        case delete = "Delete Permanently"
        var id: String { rawValue }
    }

    private var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        if node.isFolder {
            // Folder row
            VStack(spacing: 0) {
                Button {
                    if isExpanded { expandedFolders.remove(node.id) }
                    else { expandedFolders.insert(node.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(node.depth * 12 + 8))
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                // Children
                if isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(node: child, expandedFolders: $expandedFolders, activeTab: activeTab, onSelect: onSelect)
                    }
                }
            }
        } else if let note = node.note {
            // Note file row
            Button {
                onSelect(note.relativePath)
            } label: {
                NoteCardRow(note: note, isActive: activeTab == note.relativePath)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(note.title ?? note.displayName)
                .accessibilityIdentifier("scholium.noteRow.\(note.relativePath)")
                .accessibilityValue(
                    CritiquePlacement.isManagedCritiquePath(note.relativePath)
                        ? "Agent-authored Critique"
                        : appState.currentVaultRole.allowsCritique
                        ? "Work"
                        : appState.reviewDisplayState(for: note.relativePath).badgeLabel
                )
                .contextMenu {
                    Button {
                        appState.requestOpenNote(note.relativePath, inNewTab: true)
                    } label: {
                        Label("Open in New Tab", systemImage: "plus.square")
                    }
                    if appState.noteLocationScope == .workspace,
                       hasResolvedIdentity(note) {
                        Button {
                            appState.requestOpenScholia(for: note.relativePath)
                        } label: {
                            Label("Open Scholia…", systemImage: "text.bubble")
                        }
                    }
                    Divider()
                    if appState.noteLocationScope == .workspace {
                        if !CritiquePlacement.isManagedCritiquePath(note.relativePath) {
                            Button {
                                appState.noteLifecycleRequest = .duplicate(note.relativePath)
                            } label: {
                                Label("Duplicate…", systemImage: "plus.square.on.square")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        }
                        Button {
                            appState.noteLifecycleRequest = .move(note.relativePath)
                        } label: {
                            Label("Move or Rename…", systemImage: "folder")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        Divider()
                        Button {
                            pendingDestructiveAction = .setAside
                        } label: {
                            Label("Set Aside…", systemImage: "archivebox")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        Button {
                            pendingDestructiveAction = .trash
                        } label: {
                            Label("Move to Trash…", systemImage: "trash")
                        }
                        .disabled(!hasResolvedIdentity(note))
                    } else if appState.noteLocationScope == .unclassified {
                        Button {
                            appState.noteLifecycleRequest = .classify(note.relativePath)
                        } label: {
                            Label("Classify…", systemImage: "tray.and.arrow.down")
                        }
                    } else {
                        Button {
                            appState.noteLifecycleRequest = .restore(note.relativePath)
                        } label: {
                            Label("Restore…", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!hasResolvedIdentity(note))
                        if appState.noteLocationScope == .setAside {
                            Button {
                                pendingDestructiveAction = .trash
                            } label: {
                                Label("Move to Trash…", systemImage: "trash")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        } else {
                            Button(role: .destructive) {
                                pendingDestructiveAction = .delete
                            } label: {
                                Label("Delete Permanently…", systemImage: "trash.slash")
                            }
                            .disabled(!hasResolvedIdentity(note))
                        }
                    }
                    Divider()
                    Button {
                        appState.showInFinder(note.relativePath)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
                .padding(.leading, CGFloat(node.depth * 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .confirmationDialog(
                    pendingDestructiveAction?.rawValue ?? "Confirm",
                    isPresented: Binding(
                        get: { pendingDestructiveAction != nil },
                        set: { if !$0 { pendingDestructiveAction = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let action = pendingDestructiveAction {
                        Button(action.rawValue, role: action == .setAside ? nil : .destructive) {
                            perform(action, note: note)
                        }
                    }
                    Button("Cancel", role: .cancel) { pendingDestructiveAction = nil }
                } message: {
                    Text(destructiveMessage(for: pendingDestructiveAction, note: note))
                }
        }
    }

    private func destructiveMessage(for action: DestructiveAction?, note: Note) -> String {
        switch action {
        case .setAside: "Move ‘\(note.title ?? note.displayName)’ out of the active Workspace?"
        case .trash: "Move ‘\(note.title ?? note.displayName)’ to Trash?"
        case .delete: "Permanently delete ‘\(note.title ?? note.displayName)’? This removes its comments, Human Review, Dialogue records, Critique association, stable identity, Note History, and every Triptych checkpoint containing it. This cannot be undone."
        case nil: ""
        }
    }

    private func hasResolvedIdentity(_ note: Note) -> Bool {
        appState.noteLocationScope == .unclassified
            || appState.noteIdentityByPath[note.relativePath] != nil
    }

    private func perform(_ action: DestructiveAction, note: Note) {
        pendingDestructiveAction = nil
        Task {
            do {
                switch action {
                case .setAside: try await appState.setAsideNote(note.relativePath)
                case .trash: try await appState.moveNoteToTrash(note.relativePath)
                case .delete: try await appState.deleteNotePermanently(note.relativePath)
                }
            } catch {
                appState.showToast("Could not \(action.rawValue.lowercased()): \(error.localizedDescription)", kind: .error)
            }
        }
    }
}

// MARK: - Note Card Row

struct NoteCardRow: View {
    @EnvironmentObject private var appState: AppState
    let note: Note
    let isActive: Bool

    private var modifiedString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.fileModifiedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(note.title ?? note.displayName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if appState.currentVaultRole.allowsHumanReview {
                        Image(systemName: reviewBadgeSymbol)
                            .font(.system(size: 10))
                            .foregroundStyle(reviewBadgeColor)
                            .help(reviewBadgeLabel)
                            .accessibilityLabel(reviewBadgeLabel)
                    }
                }
                Text(modifiedString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let status = note.status {
                Text(status.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var reviewBadgeSymbol: String {
        reviewDisplayState.badgeSymbol
    }

    private var reviewBadgeColor: Color {
        reviewDisplayState.badgeColor
    }

    private var reviewBadgeLabel: String {
        reviewDisplayState.badgeLabel
    }

    private var reviewDisplayState: HumanReviewDisplayState {
        appState.reviewDisplayState(for: note.relativePath)
    }
}

private extension HumanReviewDisplayState {
    var badgeSymbol: String {
        switch self {
        case .notReviewed: "circle"
        case .reviewed: "checkmark.circle.fill"
        case .qualified: "checkmark.seal.fill"
        case .unqualified: "xmark.seal.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .notReviewed: .secondary.opacity(0.4)
        case .reviewed: .secondary
        case .qualified: .green
        case .unqualified: .red
        }
    }

    var badgeLabel: String {
        switch self {
        case .notReviewed: "Not reviewed"
        case .reviewed: "Reviewed"
        case .qualified: "Qualified"
        case .unqualified: "Unqualified"
        }
    }
}
