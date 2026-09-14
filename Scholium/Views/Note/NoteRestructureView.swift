import ScholiumContracts
import SwiftUI

struct NoteRestructureView: View {
    @Environment(\.dismiss) private var dismiss
    let request: WindowNoteRestructureRequest
    let prepare: @MainActor (NoteRestructureRequest) async throws -> NoteRestructurePreview
    let commit: @MainActor (NoteRestructurePreview) async throws -> Void
    @State private var query = ""
    @State private var destinationID: String?
    @State private var newPath = ""
    @State private var preview: NoteRestructurePreview?
    @State private var comparisons: [VaultQualifiedNoteID: ExactSourceComparison] = [:]
    @State private var isWorking = false
    @State private var operationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var propertyConflicts: [NoteRestructurePropertyConflict] = []
    @State private var propertyResolutions: [String: NoteRestructurePropertyResolution] = [:]

    @State private var searchFocusRequest = UUID()
    @State private var expandedFiles: Set<VaultQualifiedNoteID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
            Group {
                if let preview {
                    changedFiles(preview)
                } else if !propertyConflicts.isEmpty {
                    propertyChoices
                } else if request.createsNote {
                    TextField("New note path", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("scholium.restructure.newPath")
                        .padding(.horizontal, ScholiumMetrics.ResearchSheet.contentInset)
                        .padding(.bottom, ScholiumMetrics.ResearchSheet.contentInset)
                } else {
                    destinationPicker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(isWorking)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(ScholiumMetrics.ResearchSheet.contentInset)
                    .accessibilityIdentifier("scholium.restructure.error")
            }
            Divider()
            footer
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.NoteRestructure.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.NoteRestructure.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.NoteRestructure.minimumHeight,
            idealHeight: ScholiumMetrics.ResearchSheet.NoteRestructure.idealHeight
        )
        .presentationSizing(.fitted)
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .interactiveDismissDisabled(isWorking)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scholium.restructure")
        .onDisappear { if preview == nil { operationTask?.cancel() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
            Text(preview == nil ? request.title.replacingOccurrences(of: "…", with: "") : ScholiumL10n.string("Review Changes"))
                .font(.headline).accessibilityHeading(.h1)
            LabeledContent("Source Note") {
                Text(verbatim: request.source.relativePath)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            .font(.callout)
            Text(consequence).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let preview {
                HStack(alignment: .firstTextBaseline) {
                    LabeledContent("Destination") {
                        Text(verbatim: preview.destination.relativePath)
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                    Button("Change…") { changeDestination() }
                        .disabled(isWorking)
                        .accessibilityLabel("Change destination note")
                }
                .padding(.top, ScholiumMetrics.ResearchSheet.fieldSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
            ContextSearchField(
                text: $query, prompt: "Find a destination note", identifier: "scholium.restructure.search",
                focusRequest: searchFocusRequest,
                navigate: { _ in if destination != nil && !isWorking { perform() } })
            NativeResearchTable(
                columns: [
                    .init(id: "name", title: ScholiumL10n.string("Name")),
                    .init(
                        id: "folder", title: ScholiumL10n.string("Folder"),
                        width: ScholiumMetrics.ResearchSheet.NoteRestructure.folderColumnWidth, secondary: true),
                ],
                rows: filteredDestinations.map { target in
                    .init(id: target.id, cells: [Self.noteName(target.relativePath), Self.folderName(target.relativePath)], help: target.relativePath)
                },
                selection: $destinationID, accessibilityLabel: ScholiumL10n.string("Destination note"),
                identifier: "scholium.restructure.destinations",
                primaryAction: { _ in
                    if destination != nil && !isWorking { perform() }
                }
            )
            .overlay {
                if filteredDestinations.isEmpty {
                    ContentUnavailableView(
                        request.destinations.isEmpty ? "No destination notes" : "No matching notes",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            request.destinations.isEmpty
                                ? "Create another note in this vault to use as the destination." : "Try a different note name or folder.")
                    )
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: query) {
                if !filteredDestinations.contains(where: { $0.id == destinationID }) { destinationID = nil }
            }
        }
        .padding(.horizontal, ScholiumMetrics.ResearchSheet.contentInset)
        .padding(.bottom, ScholiumMetrics.ResearchSheet.contentInset)
    }

    private func changedFiles(_ preview: NoteRestructurePreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                ForEach(preview.edits, id: \.note) { edit in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedFiles.contains(edit.note) },
                            set: { if $0 { expandedFiles.insert(edit.note) } else { expandedFiles.remove(edit.note) } }
                        )
                    ) {
                        if let comparison = comparisons[edit.note] {
                            ExactSourceComparisonView(
                                comparison: comparison,
                                startingLabel: "Current Source", endingLabel: "Proposed Source",
                                startingOnlyLabel: "Removed", endingOnlyLabel: "Added",
                                identifierPrefix: "scholium.restructure.diff")
                        } else {
                            Text(edit.after ?? edit.before ?? "")
                                .font(ScholiumTypography.exact(.body)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: edit.note.relativePath)
                                .lineLimit(2).truncationMode(.middle)
                            Spacer()
                            if edit.before == nil { Text("Create Note").foregroundStyle(.secondary) }
                            if edit.after == nil { Text("Move to Trash…").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
        }
    }

    private var propertyChoices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                Text("Choose which authored entry to keep for each property. Other properties are retained in the merge preview.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                ForEach(propertyConflicts) { conflict in
                    VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                        Text(verbatim: conflict.key).font(.headline).accessibilityHeading(.h2)
                        LabeledContent("Destination Note") {
                            Text(verbatim: conflict.destinationEntry)
                                .font(ScholiumTypography.exact(.body)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        LabeledContent("Source Note") {
                            Text(verbatim: conflict.sourceEntry)
                                .font(ScholiumTypography.exact(.body)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Picker(
                            "Keep property from",
                            selection: Binding<NoteRestructurePropertyResolution?>(
                                get: { propertyResolutions[conflict.key] },
                                set: { propertyResolutions[conflict.key] = $0 }
                            )
                        ) {
                            Text("Choose…").tag(nil as NoteRestructurePropertyResolution?)
                            Text("Destination Note").tag(NoteRestructurePropertyResolution.keepDestination as NoteRestructurePropertyResolution?)
                            Text("Source Note").tag(NoteRestructurePropertyResolution.useSource as NoteRestructurePropertyResolution?)
                        }
                        .accessibilityLabel(Text(verbatim: ScholiumL10n.string("Keep property from") + ": " + conflict.key))
                        .accessibilityIdentifier("scholium.restructure.property.\(conflict.key)")
                    }
                }
                Button("Change destination note") { changeDestination() }
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
        }
        .accessibilityIdentifier("scholium.restructure.properties")
    }

    private var footer: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            if isWorking {
                ProgressView().controlSize(.small)
                Text(preview == nil ? "Preparing Preview…" : "Reorganizing notes")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let preview {
                Text("Changed notes: \(preview.edits.count)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: ScholiumMetrics.ResearchSheet.footerControlSpacing)
            Button("Cancel") {
                operationTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction).disabled(isWorking && preview != nil)
            .accessibilityIdentifier("scholium.restructure.cancel")
            Button(preview == nil ? ScholiumL10n.string("Preview Changes") : commitTitle) { perform() }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || (preview == nil && (destination == nil || propertyConflicts.contains { propertyResolutions[$0.key] == nil })))
                .accessibilityIdentifier("scholium.restructure.confirm")
        }
    }

    private var consequence: String {
        if request.isMerge { return ScholiumL10n.string("Append this note to the destination, then move the original to the system Trash.") }
        if request.createsNote { return ScholiumL10n.string("Create a note in this vault and replace the passage with a link.") }
        if request.action == .copy { return ScholiumL10n.string("Append a copy to the destination; the source stays in place.") }
        return ScholiumL10n.string("Append the passage to the destination and leave a link in this note.")
    }

    private var commitTitle: String {
        if request.isMerge { return ScholiumL10n.string("Merge Notes") }
        if request.createsNote { return ScholiumL10n.string("Extract Passage") }
        return request.action == .copy ? ScholiumL10n.string("Copy Passage") : ScholiumL10n.string("Move Passage")
    }

    private func changeDestination() {
        preview = nil
        comparisons = [:]
        expandedFiles = []
        errorMessage = nil
        propertyConflicts = []
        propertyResolutions = [:]
        searchFocusRequest = UUID()
    }

    private static func noteName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private static func folderName(_ path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.isEmpty ? ScholiumL10n.string("Vault Root") : folder
    }

    private var filteredDestinations: [NoteMutationTarget] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return request.destinations.filter { needle.isEmpty || $0.relativePath.localizedStandardContains(needle) }
    }

    private var destination: NoteRestructureDestination? {
        if request.createsNote {
            let path = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : .newNote(relativePath: path.hasSuffix(".md") ? path : path + ".md")
        }
        return request.destinations.first { $0.id == destinationID }.map(NoteRestructureDestination.existing)
    }

    private func perform() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        operationTask = Task { @MainActor in
            defer {
                isWorking = false
                operationTask = nil
            }
            do {
                if let preview {
                    try await commit(preview)
                    dismiss()
                } else if let destination {
                    let prepared = try await prepare(
                        .init(
                            source: request.source, selectionUTF8: request.selectionUTF8,
                            destination: destination, operation: request.isMerge ? .merge : request.action == .copy ? .copy : .move,
                            propertyResolutions: propertyResolutions))
                    try Task.checkCancellation()
                    comparisons = try await Task.detached {
                        var result: [VaultQualifiedNoteID: ExactSourceComparison] = [:]
                        for edit in prepared.edits {
                            guard let before = edit.before, let after = edit.after else { continue }
                            result[edit.note] = try ExactSourceComparisonBuilder.build(
                                startingData: Data(before.utf8), endingData: Data(after.utf8),
                                startingRevision: DocumentFingerprint(content: before), endingRevision: DocumentFingerprint(content: after))
                        }
                        return result
                    }.value
                    try Task.checkCancellation()
                    expandedFiles = [prepared.destination]
                    preview = prepared
                }
            } catch is CancellationError {
                return
            } catch NoteRestructureError.propertyConflicts(let conflicts) {
                guard !Task.isCancelled else { return }
                propertyConflicts = conflicts
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
