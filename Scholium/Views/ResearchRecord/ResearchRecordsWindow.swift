import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

struct ResearchRecordsWindowRoute: Codable, Hashable {
    let triptychID: UUID
    let sourceWindowID: UUID
}

struct ResearchRecordsWindowRequest: Hashable, Sendable {
    let triptychID: UUID
    let sourceWindowID: UUID
    let recordID: UUID
    let stepID: UUID?

    var windowRoute: ResearchRecordsWindowRoute {
        ResearchRecordsWindowRoute(
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        )
    }
}

/// Routes selection to the one existing Records window for an originating
/// Workspace and returns Note attachments to that exact Workspace. It retains
/// no Record data or workspace authority.
@MainActor
final class ResearchRecordsWindowCoordinator {
    static let shared = ResearchRecordsWindowCoordinator()

    private struct Endpoint {
        let token: UUID
        let receive: (ResearchRecordsWindowRequest) -> Void
    }

    private struct WorkspaceEndpoint {
        let token: UUID
        let open: (VaultNoteReference) -> Void
    }

    private var endpoints: [ResearchRecordsWindowRoute: Endpoint] = [:]
    private var pending: [ResearchRecordsWindowRoute: ResearchRecordsWindowRequest] = [:]
    private var workspaceEndpoints: [UUID: WorkspaceEndpoint] = [:]

    func submit(_ request: ResearchRecordsWindowRequest) {
        let route = request.windowRoute
        if let endpoint = endpoints[route] {
            endpoint.receive(request)
        } else {
            pending[route] = request
        }
    }

    func register(
        route: ResearchRecordsWindowRoute,
        receive: @escaping (ResearchRecordsWindowRequest) -> Void
    ) -> UUID {
        let token = UUID()
        endpoints[route] = Endpoint(token: token, receive: receive)
        if let pending = pending.removeValue(forKey: route) {
            receive(pending)
        }
        return token
    }

    func unregister(route: ResearchRecordsWindowRoute, token: UUID) {
        guard endpoints[route]?.token == token else { return }
        endpoints[route] = nil
    }

    func registerWorkspace(
        windowID: UUID,
        open: @escaping (VaultNoteReference) -> Void
    ) -> UUID {
        let token = UUID()
        workspaceEndpoints[windowID] = WorkspaceEndpoint(token: token, open: open)
        return token
    }

    func unregisterWorkspace(windowID: UUID, token: UUID) {
        guard workspaceEndpoints[windowID]?.token == token else { return }
        workspaceEndpoints[windowID] = nil
    }

    @discardableResult
    func openReference(_ reference: VaultNoteReference, in windowID: UUID) -> Bool {
        guard let endpoint = workspaceEndpoints[windowID] else { return false }
        endpoint.open(reference)
        return true
    }
}

@MainActor
final class ResearchRecordsModel: ObservableObject {
    struct NoteEvidence: Identifiable {
        enum RevisionState {
            case current(VaultNoteReference)
            case earlier(VaultNoteReference)
            case unavailable
        }

        let reference: ResearchRecordNoteReference
        let state: RevisionState
        var id: String { "\(reference.noteID.uuidString)-\(reference.relation.rawValue)" }
    }

    @Published private(set) var records: [ResearchRecordRevision] = []
    @Published private(set) var visibleRecordIDs: [UUID] = []
    @Published private(set) var issues: [ResearchRecordStoreIssue] = []
    @Published var selectedRecordID: UUID?
    @Published var selectedStepID: UUID?
    @Published var query = ""
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    let triptychID: UUID
    private let loadCapabilities: @MainActor () async throws
        -> ResearchRecordsWindowCapabilities
    private var capabilities: ResearchRecordsWindowCapabilities?
    private var noteSnapshots: [WorkspaceNoteSnapshot] = []

    init(
        triptychID: UUID,
        loadCapabilities: @escaping @MainActor () async throws
            -> ResearchRecordsWindowCapabilities
    ) {
        self.triptychID = triptychID
        self.loadCapabilities = loadCapabilities
    }

    var visibleRecords: [ResearchRecordRevision] {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return visibleRecordIDs.compactMap { byID[$0] }
    }

    var selectedRecord: ResearchRecordRevision? {
        records.first { $0.id == selectedRecordID }
    }

    var selectedVisibleIndex: Int? {
        guard let selectedRecordID else { return nil }
        return visibleRecordIDs.firstIndex(of: selectedRecordID)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let capabilities = try await loadCapabilities()
            self.capabilities = capabilities
            noteSnapshots = try await capabilities.documents.snapshot()
                .flatMap(\.documents)
            try await reloadRecords(using: capabilities)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshIfChanged() async {
        guard let capabilities else { return }
        do {
            let listing = try await capabilities.records.researchRecords()
            let old = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.fingerprint) })
            let new = Dictionary(uniqueKeysWithValues: listing.records.map { ($0.id, $0.fingerprint) })
            guard old != new || issues != listing.issues else { return }
            noteSnapshots = try await capabilities.documents.snapshot()
                .flatMap(\.documents)
            records = listing.records
            issues = listing.issues
            await search()
            preserveSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search() async {
        guard let capabilities else { return }
        do {
            let response = try await capabilities.discovery.unifiedSearch(.init(
                query: query,
                providerSelection: .records,
                presentationScope: .triptych,
                executionScope: .triptych,
                noteLimit: 1,
                recordLimit: SearchContract.maximumInterfaceResults
            ))
            if let diagnostic = response.records?.diagnostics.first {
                errorMessage = diagnostic.message
                visibleRecordIDs = []
            } else {
                errorMessage = nil
                visibleRecordIDs = response.records?.results.map(\.recordID) ?? []
                issues = response.records?.isolatedIssues ?? issues
                preserveSelection()
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ revision: ResearchRecordRevision, stepID: UUID? = nil) {
        selectedRecordID = revision.id
        selectedStepID = stepID
    }

    func selectPreviousRecord() {
        guard let selectedVisibleIndex else { return }
        selectVisibleRecord(at: selectedVisibleIndex - 1)
    }

    func selectNextRecord() {
        guard let selectedVisibleIndex else { return }
        selectVisibleRecord(at: selectedVisibleIndex + 1)
    }

    func open(_ request: ResearchRecordsWindowRequest) {
        guard request.triptychID == triptychID,
              let revision = records.first(where: { $0.id == request.recordID }) else {
            selectedRecordID = request.recordID
            selectedStepID = request.stepID
            return
        }
        query = ""
        select(revision, stepID: request.stepID)
    }

    func evidence(for step: ResearchRecordStep) -> [NoteEvidence] {
        step.currentNoteReferences.map { reference in
            let matches = noteSnapshots.filter {
                $0.stableIdentity.resolvedID == reference.noteID
            }
            guard matches.count == 1, let note = matches.first else {
                return NoteEvidence(reference: reference, state: .unavailable)
            }
            let route = VaultNoteReference(
                vaultID: note.id.vaultID,
                vaultName: note.vaultRole.displayName,
                vaultRole: note.vaultRole,
                relativePath: note.id.relativePath,
                stableNoteID: reference.noteID.uuidString.lowercased()
            )
            return NoteEvidence(
                reference: reference,
                state: note.fingerprint == reference.revision
                    ? .current(route)
                    : .earlier(route)
            )
        }
    }

    private func selectVisibleRecord(at index: Int) {
        guard visibleRecordIDs.indices.contains(index),
              let revision = records.first(where: {
                  $0.id == visibleRecordIDs[index]
              }) else { return }
        select(revision)
    }

    private func reloadRecords(
        using capabilities: ResearchRecordsWindowCapabilities
    ) async throws {
        let listing = try await capabilities.records.researchRecords()
        records = listing.records
        issues = listing.issues
        await search()
        preserveSelection()
    }

    private func preserveSelection() {
        if let selectedRecordID,
           visibleRecordIDs.contains(selectedRecordID) {
            if let selectedStepID,
               selectedRecord?.record.steps.contains(where: {
                   $0.id == selectedStepID
               }) != true {
                self.selectedStepID = nil
            }
            return
        }
        selectedRecordID = visibleRecords.first?.id
        selectedStepID = nil
    }

}

struct ResearchRecordsWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private let route: ResearchRecordsWindowRoute
    @StateObject private var model: ResearchRecordsModel
    @State private var searchTask: Task<Void, Never>?
    @State private var routeToken: UUID?
    @FocusState private var focusedRecordID: UUID?

    init(
        route: ResearchRecordsWindowRoute,
        loadCapabilities: @escaping @MainActor () async throws
            -> ResearchRecordsWindowCapabilities
    ) {
        self.route = route
        _model = StateObject(wrappedValue: ResearchRecordsModel(
            triptychID: route.triptychID,
            loadCapabilities: loadCapabilities
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            collection
                .padding(.top, ScholiumMetrics.ResearchRecords.windowDragInset)
                .frame(width: ScholiumMetrics.ResearchRecords.collectionWidth)
                .scholiumSurface(.navigation)
            ScholiumStructuralRule(orientation: .vertical)
            detail
                .padding(.top, ScholiumMetrics.ResearchRecords.windowDragInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scholiumSurface(.document)
        .tint(ScholiumColorRole.accent.color)
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand { dismissWindow() }
        .task { await model.load() }
        .onAppear {
            routeToken = ResearchRecordsWindowCoordinator.shared.register(
                route: route,
                receive: model.open
            )
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await model.refreshIfChanged()
            }
        }
        .onChange(of: model.query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await model.search()
            }
        }
        .onDisappear {
            searchTask?.cancel()
            if let routeToken {
                ResearchRecordsWindowCoordinator.shared.unregister(
                    route: route,
                    token: routeToken
                )
            }
            routeToken = nil
        }
    }

    private var collection: some View {
        VStack(spacing: 0) {
            ResearchRecordsSearchField(text: $model.query)
                .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            ScholiumStructuralRule()
            collectionResults
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research Record Collection")
        .scholiumSurface(.navigation)
    }

    private var collectionResults: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            Array(model.visibleRecords.enumerated()),
                            id: \.element.id
                        ) { index, revision in
                            recordRow(revision, at: index)
                                .id(revision.id)
                        }

                        if !model.issues.isEmpty {
                            unavailableRecords
                        }
                    }
                    .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                    .padding(.bottom, ScholiumGrid.Spacing.sectionSeparation)
                }
                .onChange(of: model.selectedRecordID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            collectionState
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recordRow(
        _ revision: ResearchRecordRevision,
        at index: Int
    ) -> some View {
        let isSelected = model.selectedRecordID == revision.id
        return Button {
            model.select(revision)
        } label: {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchRecords.collectionRowSpacing
            ) {
                Text(revision.record.question)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(revision.record.lastSubstantiveAt, style: .relative)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .vertical,
                ScholiumMetrics.ResearchRecords.collectionRowVerticalInset
            )
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
        }
        .buttonStyle(ScholiumContentControlButtonStyle(
            isSelected: isSelected,
            isFocused: focusedRecordID == revision.id,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        ))
        .scholiumActivationFocus($focusedRecordID, equals: revision.id)
        .overlay(alignment: .bottom) {
            if index < model.visibleRecords.count - 1 {
                ScholiumStructuralRule()
            }
        }
        .onMoveCommand(perform: moveCollectionSelection)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            "scholium.researchRecords.row." + revision.id.uuidString.lowercased()
        )
    }

    private var unavailableRecords: some View {
        Group {
            ScholiumStructuralRule()
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            DisclosureGroup("Unavailable") {
                ForEach(model.issues) { issue in
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.labelAccessoryGap
                    ) {
                        Text(issue.fileName)
                            .font(ScholiumTypography.interface(.compact))
                        Text(issue.reason)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                    .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                    .textSelection(.enabled)
                }
            }
            .font(ScholiumTypography.interface(.body))
        }
    }

    @ViewBuilder
    private var collectionState: some View {
        if model.isLoading {
            ScholiumContentStateView(
                "Loading Research Records…",
                indicator: .progress
            )
            .scholiumSurface(.navigation)
        } else if model.visibleRecords.isEmpty {
            if model.query.isEmpty {
                ScholiumContentStateView(
                    "No Research Records",
                    detail: Text(model.errorMessage
                        ?? "Agents have not recorded substantive progress for this Triptych."),
                    indicator: .symbol("text.book.closed"),
                    density: .compact
                )
                .scholiumSurface(.navigation)
            } else {
                ScholiumContentStateView(
                    "No Results",
                    detail: Text(model.errorMessage ?? "Try a different Record query."),
                    indicator: .symbol("magnifyingglass"),
                    density: .compact
                )
                .scholiumSurface(.navigation)
            }
        }
    }

    private func moveCollectionSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            model.selectPreviousRecord()
        case .down:
            model.selectNextRecord()
        default:
            return
        }
        focusedRecordID = model.selectedRecordID
    }

    @ViewBuilder
    private var detail: some View {
        if model.isLoading {
            ScholiumContentStateView(
                "Loading Research Records…",
                indicator: .progress
            )
                .scholiumSurface(.document)
        } else if let revision = model.selectedRecord {
            VStack(spacing: 0) {
                recordHeader(revision)
                    .frame(
                        maxWidth: ScholiumMetrics.ResearchRecords.readingMeasure,
                        alignment: .leading
                    )
                    .padding(
                        .horizontal,
                        ScholiumMetrics.ResearchRecords.readingHorizontalInset
                    )
                    .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
                    .frame(maxWidth: .infinity)
                ScholiumStructuralRule()

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(
                                Array(revision.record.steps.enumerated()),
                                id: \.element.id
                            ) { index, step in
                                stepView(
                                    step,
                                    number: index + 1,
                                    drawsTopRule: index > 0
                                )
                                .id(step.id)
                            }
                            recordDetails(revision)
                        }
                        .frame(
                            maxWidth: ScholiumMetrics.ResearchRecords.readingMeasure,
                            alignment: .leading
                        )
                        .padding(
                            .horizontal,
                            ScholiumMetrics.ResearchRecords.readingHorizontalInset
                        )
                        .padding(
                            .bottom,
                            ScholiumMetrics.ResearchRecords.readingVerticalInset
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .onChange(of: model.selectedStepID) { _, stepID in
                        guard let stepID else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(stepID, anchor: .center)
                        }
                    }
                }
            }
            .scholiumSurface(.document)
        } else if model.query.isEmpty {
            ScholiumContentStateView(
                "Select a Research Record",
                detail: Text("Choose a current inquiry from the collection."),
                indicator: .symbol("text.book.closed")
            )
            .scholiumSurface(.document)
        } else {
            ScholiumContentStateView(
                "No Results",
                detail: Text("Try a different Record query."),
                indicator: .symbol("magnifyingglass")
            )
            .scholiumSurface(.document)
        }
    }

    private func recordHeader(_ revision: ResearchRecordRevision) -> some View {
        Text(revision.record.question)
            .font(ScholiumTypography.scholarly(.title))
            .accessibilityAddTraits(.isHeader)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepView(
        _ step: ResearchRecordStep,
        number: Int,
        drawsTopRule: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.ResearchRecords.stepHeaderSpacing
        ) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Step \(number)")
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(step.submittedBy.displayName)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.agentAuthorship)
                Spacer()
                Text(step.recordedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "scholium.researchRecords.step.\(step.id.uuidString.lowercased())"
            )
            ResearchRecordMarkdownView(source: step.currentBodyMarkdown)
            if !step.currentRevisesStepIDs.isEmpty || !step.corrections.isEmpty {
                Text(revisionSummary(step))
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            noteReferences(step)
        }
        .padding(.vertical, ScholiumMetrics.ResearchRecords.stepVerticalInset)
        .overlay(alignment: .top) {
            if drawsTopRule { ScholiumStructuralRule() }
        }
    }

    @ViewBuilder
    private func noteReferences(_ step: ResearchRecordStep) -> some View {
        let evidence = model.evidence(for: step)
        if !evidence.isEmpty {
            HStack(
                alignment: .center,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                Text("Notes")
                    .font(ScholiumTypography.interface(.rowTitle))
                    .fixedSize()

                ScrollView(.horizontal) {
                    LazyHStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        ForEach(evidence) { item in
                            Button {
                                openEvidence(item)
                            } label: {
                                HStack(
                                    alignment: .center,
                                    spacing: ScholiumGrid.Spacing.inlineControlGap
                                ) {
                                    Image(systemName: "doc.text")
                                        .accessibilityHidden(true)
                                    Text(evidenceTitle(item))
                                        .lineLimit(1)
                                    Text(referenceRelation(item.reference.relation))
                                        .scholiumForeground(.secondaryText)
                                    if let exceptionalState = exceptionalEvidenceState(item) {
                                        Text(exceptionalState.title)
                                            .scholiumForeground(exceptionalState.colorRole)
                                    }
                                }
                                .font(ScholiumTypography.interface(.compact))
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!evidenceIsAvailable(item))
                            .help(evidenceButtonHelp(item))
                            .accessibilityValue(evidenceAccessibilityValue(item))
                            .accessibilityIdentifier(
                                "scholium.researchRecords.reference."
                                    + step.id.uuidString.lowercased()
                                    + "."
                                    + item.reference.noteID.uuidString.lowercased()
                                    + "."
                                    + item.reference.relation.rawValue
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .padding(.top, ScholiumMetrics.ResearchRecords.referenceSectionSpacing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Referenced Notes")
        }
    }

    private func recordDetails(_ revision: ResearchRecordRevision) -> some View {
        DisclosureGroup("Record Details") {
            exactValue("Record", revision.id.uuidString.lowercased())
            exactValue("Fingerprint", revision.fingerprint.sha256)
        }
        .font(ScholiumTypography.interface(.body))
        .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
    }

    private func exactValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(label)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Text(value)
                .font(ScholiumTypography.exact(.small))
                .textSelection(.enabled)
        }
        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
    }

    private func openEvidence(_ evidence: ResearchRecordsModel.NoteEvidence) {
        let route: VaultNoteReference
        switch evidence.state {
        case .current(let value), .earlier(let value): route = value
        case .unavailable: return
        }
        if ResearchRecordsWindowCoordinator.shared.openReference(
            route,
            in: self.route.sourceWindowID
        ) {
            dismissWindow()
        }
    }

    private func evidenceTitle(_ evidence: ResearchRecordsModel.NoteEvidence) -> String {
        switch evidence.state {
        case .current(let route), .earlier(let route):
            String(route.relativePath.dropLast(route.relativePath.hasSuffix(".md") ? 3 : 0))
        case .unavailable: evidence.reference.noteID.uuidString.lowercased()
        }
    }

    private func evidenceState(_ evidence: ResearchRecordsModel.NoteEvidence) -> String {
        switch evidence.state {
        case .current: String(localized: "Current revision")
        case .earlier: String(localized: "Earlier revision")
        case .unavailable: String(localized: "Note unavailable")
        }
    }

    private func evidenceAccessibilityValue(
        _ evidence: ResearchRecordsModel.NoteEvidence
    ) -> String {
        referenceRelation(evidence.reference.relation) + ", " + evidenceState(evidence)
    }

    private func exceptionalEvidenceState(
        _ evidence: ResearchRecordsModel.NoteEvidence
    ) -> (title: String, colorRole: ScholiumColorRole)? {
        switch evidence.state {
        case .current:
            nil
        case .earlier:
            (String(localized: "Earlier"), .attention)
        case .unavailable:
            (String(localized: "Unavailable"), .mutedText)
        }
    }

    private func evidenceButtonHelp(
        _ evidence: ResearchRecordsModel.NoteEvidence
    ) -> String {
        switch evidence.state {
        case .current(let route), .earlier(let route):
            String(localized: "Open \(route.relativePath)")
        case .unavailable:
            String(localized: "This Note is unavailable")
        }
    }

    private func evidenceIsAvailable(
        _ evidence: ResearchRecordsModel.NoteEvidence
    ) -> Bool {
        if case .unavailable = evidence.state { return false }
        return true
    }

    private func referenceRelation(_ relation: ResearchRecordNoteRelation) -> String {
        switch relation {
        case .basis: String(localized: "Basis")
        case .modified: String(localized: "Modified")
        }
    }

    private func revisionSummary(_ step: ResearchRecordStep) -> String {
        var parts: [String] = []
        if !step.currentRevisesStepIDs.isEmpty {
            parts.append(String(localized: "Revises \(step.currentRevisesStepIDs.count) earlier step(s)"))
        }
        if !step.corrections.isEmpty {
            parts.append(String(localized: "\(step.corrections.count) clerical correction(s)"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ResearchRecordsSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = ScholiumL10n.string("Search records")
        searchField.sendsSearchStringImmediately = true
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchChanged(_:))
        searchField.setAccessibilityLabel(ScholiumL10n.string("Search records"))
        searchField.setAccessibilityIdentifier("scholium.researchRecords.search")
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ResearchRecordsSearchField

        init(parent: ResearchRecordsSearchField) {
            self.parent = parent
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }
    }
}

private struct ResearchRecordMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            ForEach(Array(ResearchRecordMarkdownProjection(source).blocks.enumerated()), id: \.offset) {
                _, block in
                switch block.kind {
                case .paragraph:
                    markdownText(block.text)
                case .unordered:
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ScholiumGrid.Spacing.inlineControlGap
                    ) {
                        Text("•")
                        markdownText(block.text)
                    }
                case .ordered(let index):
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ScholiumGrid.Spacing.inlineControlGap
                    ) {
                        Text("\(index).")
                        markdownText(block.text)
                    }
                case .quote:
                    HStack(
                        alignment: .top,
                        spacing: ScholiumGrid.Spacing.nestedContentInset
                    ) {
                        Rectangle()
                            .fill(ScholiumColorRole.separator.color)
                            .frame(width: ScholiumGrid.Spacing.opticalAlignmentAdjustment)
                        markdownText(block.text)
                    }
                case .literal:
                    Text(block.text)
                        .font(ScholiumTypography.exact(.body))
                        .textSelection(.enabled)
                }
            }
        }
        .font(ScholiumTypography.scholarly(.body))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownText(_ source: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        return Text(attributed)
    }
}

struct ResearchRecordMarkdownProjection: Hashable {
    struct Block: Hashable {
        enum Kind: Hashable {
            case paragraph
            case unordered
            case ordered(Int)
            case quote
            case literal
        }
        let kind: Kind
        let text: String
    }

    let blocks: [Block]

    init(_ source: String) {
        var result: [Block] = []
        var paragraph: [String] = []
        var fence: String?
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let activeFence = fence {
                flushParagraph()
                result.append(Block(kind: .literal, text: line))
                if trimmed.hasPrefix(activeFence) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                fence = String(trimmed.prefix(3))
                result.append(Block(kind: .literal, text: line))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                continue
            }
            if Self.isLiteral(trimmed) {
                flushParagraph()
                result.append(Block(kind: .literal, text: line))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                result.append(Block(kind: .quote, text: String(trimmed.dropFirst(2))))
            } else if ["- ", "* ", "+ "].contains(where: trimmed.hasPrefix) {
                flushParagraph()
                result.append(Block(kind: .unordered, text: String(trimmed.dropFirst(2))))
            } else if let ordered = Self.orderedItem(trimmed) {
                flushParagraph()
                result.append(Block(kind: .ordered(ordered.index), text: ordered.text))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        blocks = result
    }

    private static func isLiteral(_ line: String) -> Bool {
        line.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil
            || line.hasPrefix("<")
            || line.contains("![")
            || line == "---" || line == "***" || line == "___"
            || (line.hasPrefix("|") && line.hasSuffix("|"))
    }

    private static func orderedItem(_ line: String) -> (index: Int, text: String)? {
        guard let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression),
              let separator = line[..<range.upperBound].firstIndex(of: "."),
              let index = Int(line[..<separator]) else { return nil }
        return (index, String(line[range.upperBound...]))
    }
}
