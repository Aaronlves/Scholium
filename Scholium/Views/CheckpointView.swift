import ScholiumContracts
import SwiftUI

struct CreateCheckpointView: View {
    @Environment(\.dismiss) private var dismiss
    let createCheckpoint: (String) async throws -> Void
    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Create Checkpoint", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.title2.weight(.semibold))
            Text("A manual checkpoint is a self-contained copy of the complete Triptych. It remains until you delete its folder in Finder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Checkpoint name", text: $name)
                .onSubmit { create() }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .scholiumForeground(.destructive)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Checkpoint") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func create() {
        Task { @MainActor in
            isCreating = true
            defer { isCreating = false }
            do {
                try await createCheckpoint(name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct RestoreCheckpointView: View {
    @ObservedObject private var controller: ResearchController
    @Environment(\.dismiss) private var dismiss

    let restoreCheckpoint: (
        UUID,
        TriptychCheckpointRestoreSelection
    ) async throws -> Void
    let revealCheckpoints: () -> Void

    @State private var checkpoints: [TriptychCheckpoint] = []
    @State private var selectedCheckpointID: UUID?
    @State private var changes: [TriptychCheckpointChange] = []
    @State private var selectedFiles: Set<TriptychCheckpointFileKey> = []
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var confirmCompleteRestore = false
    @State private var errorMessage: String?
    @State private var listingError: String?

    init(
        controller: ResearchController,
        restoreCheckpoint: @escaping (
            UUID,
            TriptychCheckpointRestoreSelection
        ) async throws -> Void,
        revealCheckpoints: @escaping () -> Void
    ) {
        _controller = ObservedObject(wrappedValue: controller)
        self.restoreCheckpoint = restoreCheckpoint
        self.revealCheckpoints = revealCheckpoints
    }

    private var selectedCheckpoint: TriptychCheckpoint? {
        checkpoints.first { $0.id == selectedCheckpointID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Restore from Checkpoint")
                        .font(.title2.weight(.semibold))
                    Text("Compare the current Triptych, then restore selected notes or the complete checkpoint.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading checkpoints…")
                Spacer()
            } else if checkpoints.isEmpty, let listingError {
                ContentUnavailableView(
                    "Checkpoints Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(listingError)
                )
            } else if checkpoints.isEmpty {
                ContentUnavailableView(
                    "No Checkpoints",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Create a checkpoint before substantial external work.")
                )
            } else {
                VStack(spacing: 0) {
                    if let listingError {
                        Label(listingError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .scholiumForeground(.attention)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    GeometryReader { geometry in
                        if geometry.size.width < 780 {
                            VStack(spacing: 0) {
                                checkpointList
                                    .frame(minHeight: 160, maxHeight: .infinity)
                                Divider()
                                changeList
                                    .frame(minHeight: 220, maxHeight: .infinity)
                            }
                        } else {
                            HSplitView {
                                checkpointList
                                    .frame(minWidth: 240, idealWidth: 280)

                                changeList
                                    .frame(minWidth: 500, maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 0, idealWidth: 980, minHeight: 560, idealHeight: 700)
        .task { await load() }
        .onChange(of: selectedCheckpointID) { _, id in
            guard let id else { return }
            Task { await loadComparison(id) }
        }
        .confirmationDialog(
            "Restore the Complete Triptych?",
            isPresented: $confirmCompleteRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Complete Triptych", role: .destructive) {
                restore(.completeTriptych)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scholium first creates Before Restore. Files created after this checkpoint move to Trash; files changed, moved, or deleted are restored from the selected checkpoint.")
        }
        .alert("Checkpoint Restore Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Inspecting", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var changeList: some View {
        VStack(spacing: 0) {
            if let selectedCheckpoint {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCheckpoint.name).font(.headline)
                        Text(selectedCheckpoint.triptychFingerprint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
            }
            List {
                ForEach(TriptychCheckpointChangeKind.allCasesForDisplay, id: \.self) { kind in
                    let matching = changes.filter { $0.kind == kind }
                    if !matching.isEmpty {
                        Section(kind.displayName) {
                            ForEach(Array(matching.enumerated()), id: \.offset) { _, change in
                                HStack(alignment: .top, spacing: 10) {
                                    if let key = restorableKey(change) {
                                        Toggle(isOn: fileSelection(key)) { EmptyView() }
                                            .toggleStyle(.checkbox)
                                            .labelsHidden()
                                            .accessibilityLabel("Restore \(change.currentPath ?? change.checkpointPath ?? "unknown file")")
                                            .accessibilityHint("Includes this note in the selective checkpoint restore")
                                    } else {
                                        Color.clear.frame(width: 16, height: 16)
                                    }
                                    Image(systemName: kind.symbol)
                                        .scholiumForeground(kind.colorRole)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.currentPath ?? change.checkpointPath ?? "Unknown file")
                                            .lineLimit(1)
                                        if change.kind == .moved,
                                           let old = change.checkpointPath,
                                           let current = change.currentPath {
                                            Text("Checkpoint: \(old) — Current: \(current)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(change.area.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if changes.isEmpty, selectedCheckpoint != nil {
                    ContentUnavailableView(
                        "No Differences",
                        systemImage: "checkmark.circle",
                        description: Text("The current Triptych matches this checkpoint.")
                    )
                }
            }
        }
    }

    private var checkpointList: some View {
        List(checkpoints, selection: $selectedCheckpointID) { checkpoint in
            VStack(alignment: .leading, spacing: 3) {
                Text(checkpoint.name).fontWeight(.medium)
                Text("\(checkpoint.kind.displayName) — \(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(checkpoint.id)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reveal Checkpoints in Finder", action: revealCheckpoints)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Restore Selected Notes") {
                restore(.mappedFiles(Set(selectedFiles.compactMap { key in
                    guard let change = changes.first(where: {
                        $0.area == key.area && $0.checkpointPath == key.relativePath
                    }) else { return nil }
                    let destination = TriptychCheckpointFileKey(
                        area: change.area,
                        relativePath: change.currentPath ?? key.relativePath
                    )
                    return TriptychCheckpointFileRestore(source: key, destination: destination)
                })))
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFiles.isEmpty || isRestoring)
            Button("Restore Complete Triptych") { confirmCompleteRestore = true }
                .disabled(
                    selectedCheckpointID == nil
                        || selectedCheckpoint?.kind == .researchContinuation
                        || isRestoring
                )
        }
        .padding(16)
    }

    private func load() async {
        do {
            let listing = try await controller.checkpoints()
            checkpoints = listing.checkpoints
            listingError = listing.unreadableEntries.isEmpty
                ? nil
                : "Some checkpoint folders could not be read and remain unchanged.\n\n"
                    + listing.unreadableEntries.joined(separator: "\n")
        } catch {
            checkpoints = []
            listingError = error.localizedDescription
        }
        selectedCheckpointID = checkpoints.first?.id
        isLoading = false
        if let selectedCheckpointID { await loadComparison(selectedCheckpointID) }
    }

    private func loadComparison(_ id: UUID) async {
        do {
            changes = try await controller.checkpointComparison(id)
            selectedFiles = Set(changes.compactMap(restorableKey))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ selection: TriptychCheckpointRestoreSelection) {
        guard let selectedCheckpointID else { return }
        Task { @MainActor in
            isRestoring = true
            defer { isRestoring = false }
            do {
                try await restoreCheckpoint(selectedCheckpointID, selection)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorableKey(_ change: TriptychCheckpointChange) -> TriptychCheckpointFileKey? {
        guard change.kind != .created, change.kind != .unchanged,
              let path = change.checkpointPath else { return nil }
        return TriptychCheckpointFileKey(area: change.area, relativePath: path)
    }

    private func fileSelection(_ key: TriptychCheckpointFileKey) -> Binding<Bool> {
        Binding(
            get: { selectedFiles.contains(key) },
            set: { selected in
                if selected { selectedFiles.insert(key) }
                else { selectedFiles.remove(key) }
            }
        )
    }
}

private extension TriptychCheckpointKind {
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual"
        case .researchContinuation: "Continuation Recovery"
        }
    }
}

private extension TriptychCheckpointChangeKind {
    static var allCasesForDisplay: [Self] { [.changed, .moved, .deleted, .created, .unchanged] }

    var displayName: String {
        switch self {
        case .created: "Created Since Checkpoint"
        case .changed: "Changed"
        case .moved: "Moved"
        case .deleted: "Deleted Since Checkpoint"
        case .unchanged: "Unchanged"
        }
    }

    var symbol: String {
        switch self {
        case .created: "plus.circle"
        case .changed: "pencil.circle"
        case .moved: "arrow.right.circle"
        case .deleted: "minus.circle"
        case .unchanged: "checkmark.circle"
        }
    }

    var colorRole: ScholiumColorRole {
        switch self {
        case .created, .changed, .moved, .deleted: .attention
        case .unchanged: .secondaryText
        }
    }
}
