import Foundation
import ScholiumContracts
import SwiftUI

struct ResearchRecordsWindowRoute: Codable, Hashable {
    let triptychID: UUID
}

struct ResearchRecordsWindowRequest: Hashable, Sendable {
    let triptychID: UUID
    let recordID: UUID
    let stepID: UUID?
}

/// Routes selection to the one existing Records window for a Triptych. It
/// retains no Record data or workspace authority.
@MainActor
final class ResearchRecordsWindowCoordinator {
    static let shared = ResearchRecordsWindowCoordinator()

    private struct Endpoint {
        let token: UUID
        let receive: (ResearchRecordsWindowRequest) -> Void
    }

    private var endpoints: [UUID: Endpoint] = [:]
    private var pending: [UUID: ResearchRecordsWindowRequest] = [:]

    func submit(_ request: ResearchRecordsWindowRequest) {
        if let endpoint = endpoints[request.triptychID] {
            endpoint.receive(request)
        } else {
            pending[request.triptychID] = request
        }
    }

    func register(
        triptychID: UUID,
        receive: @escaping (ResearchRecordsWindowRequest) -> Void
    ) -> UUID {
        let token = UUID()
        endpoints[triptychID] = Endpoint(token: token, receive: receive)
        if let pending = pending.removeValue(forKey: triptychID) {
            receive(pending)
        }
        return token
    }

    func unregister(triptychID: UUID, token: UUID) {
        guard endpoints[triptychID]?.token == token else { return }
        endpoints[triptychID] = nil
    }
}

@MainActor
final class ResearchRecordsWindowModel: ObservableObject {
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
    @Published var showsEvidence = true
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    let triptychID: UUID
    private let workspaceStore: WorkspaceStore
    private var capabilities: WindowWorkspaceCapabilities?
    private var noteSnapshots: [WorkspaceNoteSnapshot] = []

    init(
        triptychID: UUID,
        workspaceStore: WorkspaceStore
    ) {
        self.triptychID = triptychID
        self.workspaceStore = workspaceStore
    }

    var visibleRecords: [ResearchRecordRevision] {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return visibleRecordIDs.compactMap { byID[$0] }
    }

    var selectedRecord: ResearchRecordRevision? {
        records.first { $0.id == selectedRecordID }
    }

    var selectedStep: ResearchRecordStep? {
        guard let selectedRecord else { return nil }
        return selectedRecord.record.steps.first { $0.id == selectedStepID }
            ?? selectedRecord.record.steps.last
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let capabilities = try await workspaceStore.workspaceCapabilities(
                id: triptychID
            )
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
            let listing = try await capabilities.agentCollaboration.researchRecords()
            let old = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.fingerprint) })
            let new = Dictionary(uniqueKeysWithValues: listing.records.map { ($0.id, $0.fingerprint) })
            guard old != new || issues != listing.issues else { return }
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
        selectedStepID = stepID ?? revision.record.steps.last?.id
    }

    func open(_ request: ResearchRecordsWindowRequest) {
        guard request.triptychID == triptychID,
              let revision = records.first(where: { $0.id == request.recordID }) else {
            selectedRecordID = request.recordID
            selectedStepID = request.stepID
            return
        }
        select(revision, stepID: request.stepID)
    }

    func selectStep(_ step: ResearchRecordStep) {
        selectedStepID = step.id
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

    private func reloadRecords(
        using capabilities: WindowWorkspaceCapabilities
    ) async throws {
        let listing = try await capabilities.agentCollaboration.researchRecords()
        records = listing.records
        issues = listing.issues
        await search()
        preserveSelection()
    }

    private func preserveSelection() {
        if let selectedRecordID,
           records.contains(where: { $0.id == selectedRecordID }) {
            if selectedStepID == nil { selectedStepID = selectedRecord?.record.steps.last?.id }
            return
        }
        selectedRecordID = visibleRecords.first?.id ?? records.first?.id
        selectedStepID = selectedRecord?.record.steps.last?.id
    }

}

struct ResearchRecordsWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model: ResearchRecordsWindowModel
    @State private var searchTask: Task<Void, Never>?
    @State private var routeToken: UUID?

    init(route: ResearchRecordsWindowRoute, workspaceStore: WorkspaceStore) {
        _model = StateObject(wrappedValue: ResearchRecordsWindowModel(
            triptychID: route.triptychID,
            workspaceStore: workspaceStore
        ))
    }

    var body: some View {
        HSplitView {
            collection
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            if model.showsEvidence, let step = model.selectedStep {
                evidenceRail(step)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
        }
        .scholiumSurface(.document)
        .navigationTitle(String(localized: "Research Records"))
        .toolbar {
            ToolbarItem {
                Button {
                    model.showsEvidence.toggle()
                } label: {
                    Label("Evidence", systemImage: "sidebar.trailing")
                }
                .help(model.showsEvidence ? "Hide Evidence" : "Show Evidence")
            }
        }
        .task { await model.load() }
        .onAppear {
            routeToken = ResearchRecordsWindowCoordinator.shared.register(
                triptychID: model.triptychID,
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
                    triptychID: model.triptychID,
                    token: routeToken
                )
            }
            routeToken = nil
        }
    }

    private var collection: some View {
        VStack(spacing: 0) {
            TextField("Search records", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding(16)
                .accessibilityIdentifier("scholium.researchRecords.search")
            Divider()
            if model.isLoading {
                ProgressView("Loading Research Records…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleRecords.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? "No Research Records" : "No Results",
                    systemImage: "text.book.closed",
                    description: Text(model.errorMessage ??
                        (model.query.isEmpty
                            ? "Agents have not recorded substantive progress for this Triptych."
                            : "Try a different Record query."))
                )
            } else {
                List(model.visibleRecords, selection: $model.selectedRecordID) { revision in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(revision.record.question)
                            .font(ScholiumTypography.interface(.rowTitle))
                            .lineLimit(3)
                        Text(revision.record.lastSubstantiveAt, style: .relative)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                    .padding(.vertical, 5)
                    .tag(revision.id)
                    .accessibilityIdentifier(
                        "scholium.researchRecords.row.\(revision.id.uuidString.lowercased())"
                    )
                }
                .onChange(of: model.selectedRecordID) { _, id in
                    guard let revision = model.records.first(where: { $0.id == id }) else { return }
                    model.select(revision)
                }
            }
            if !model.issues.isEmpty {
                Divider()
                DisclosureGroup("Some files could not be loaded") {
                    ForEach(model.issues) { issue in
                        Text("\(issue.fileName): \(issue.reason)")
                            .font(ScholiumTypography.interface(.small))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }
        }
        .scholiumSurface(.navigation)
    }

    @ViewBuilder
    private var detail: some View {
        if let revision = model.selectedRecord {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(revision.record.question)
                            .font(ScholiumTypography.scholarly(.title))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 24)
                        ForEach(revision.record.steps) { step in
                            stepView(step)
                                .id(step.id)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .onChange(of: model.selectedStepID) { _, stepID in
                    guard let stepID else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(stepID, anchor: .center)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Research Record",
                systemImage: "text.book.closed",
                description: Text("Choose a current inquiry from the collection.")
            )
        }
    }

    private func stepView(_ step: ResearchRecordStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.submittedBy.displayName)
                    .font(ScholiumTypography.interface(.compact))
                Spacer()
                Text(step.recordedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            ResearchRecordMarkdownView(source: step.currentBodyMarkdown)
            if !step.currentRevisesStepIDs.isEmpty || !step.corrections.isEmpty {
                Text(revisionSummary(step))
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectStep(step) }
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier(
            "scholium.researchRecords.step.\(step.id.uuidString.lowercased())"
        )
    }

    private func evidenceRail(_ step: ResearchRecordStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Evidence")
                    .font(ScholiumTypography.interface(.sectionTitle))
                evidenceSection("Basis", relation: .basis, step: step)
                evidenceSection("Modified", relation: .modified, step: step)
                DisclosureGroup("Record Details") {
                    if let revision = model.selectedRecord {
                        exactValue("Record", revision.id.uuidString.lowercased())
                        exactValue("Fingerprint", revision.fingerprint.sha256)
                        exactValue("Step", step.id.uuidString.lowercased())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .scholiumSurface(.apparatus)
    }

    @ViewBuilder
    private func evidenceSection(
        _ title: LocalizedStringKey,
        relation: ResearchRecordNoteRelation,
        step: ResearchRecordStep
    ) -> some View {
        let evidence = model.evidence(for: step).filter {
            $0.reference.relation == relation
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ScholiumTypography.interface(.rowTitle))
            if evidence.isEmpty {
                Text("None")
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
            } else {
                ForEach(evidence) { item in
                    Button {
                        openEvidence(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(evidenceTitle(item))
                                .font(ScholiumTypography.interface(.compact))
                            Text(evidenceState(item))
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled({
                        if case .unavailable = item.state { return true }
                        return false
                    }())
                }
            }
        }
    }

    private func exactValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Text(value)
                .font(ScholiumTypography.exact(.small))
                .textSelection(.enabled)
        }
        .padding(.top, 6)
    }

    private func openEvidence(_ evidence: ResearchRecordsWindowModel.NoteEvidence) {
        let route: VaultNoteReference
        switch evidence.state {
        case .current(let value), .earlier(let value): route = value
        case .unavailable: return
        }
        openWindow(
            id: "scholium-main",
            value: TriptychWindowRoute(
                triptychID: model.triptychID,
                initialDocument: route
            )
        )
    }

    private func evidenceTitle(_ evidence: ResearchRecordsWindowModel.NoteEvidence) -> String {
        switch evidence.state {
        case .current(let route), .earlier(let route): route.relativePath
        case .unavailable: evidence.reference.noteID.uuidString.lowercased()
        }
    }

    private func evidenceState(_ evidence: ResearchRecordsWindowModel.NoteEvidence) -> String {
        switch evidence.state {
        case .current: String(localized: "Current revision")
        case .earlier: String(localized: "Earlier revision")
        case .unavailable: String(localized: "Note unavailable")
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

private struct ResearchRecordMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ResearchRecordMarkdownProjection(source).blocks.enumerated()), id: \.offset) {
                _, block in
                switch block.kind {
                case .paragraph:
                    markdownText(block.text)
                case .unordered:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        markdownText(block.text)
                    }
                case .ordered(let index):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index).")
                        markdownText(block.text)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle()
                            .fill(ScholiumColorRole.separator.color)
                            .frame(width: 2)
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
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        for line in source.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
            || line.hasPrefix("```")
            || line.hasPrefix("~~~")
            || line.hasPrefix("<")
            || line.hasPrefix("![")
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
