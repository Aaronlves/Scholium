import ScholiumContracts
import SwiftUI

// MARK: - Relationship Inspector

/// Immutable workspace context and app-only Zotero effects required by the
/// Relationships inspector. Navigation remains a typed Research intent.
struct RelationshipViewContext {
    let currentVault: RegisteredVault?
    let analysesVaultID: UUID?
    let catalog: WorkspaceCatalogSnapshot?
    let attentionDismissalDays: Int
    let resolveZoteroSource: (ZoteroSourceIdentity) async throws -> ZoteroMatchResult
    let openZoteroItem: (String) async -> Void
    let confirmZoteroItem: (String, VaultNoteReference) async throws -> Void
    let didConfirmZoteroSource: (String) -> Void
    let copyResearchText: (String) -> Void
    let repairBibliographyMethod: () -> Void
}

/// Document-local research context: Attention, Zotero source identity, and
/// source-anchored Connections. Authoritative note content remains primary.
struct RelationshipView: View {
    @ObservedObject private var controller: ResearchController
    let note: WindowDocumentLocation
    let context: RelationshipViewContext
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

    init(
        note: WindowDocumentLocation,
        controller: ResearchController,
        context: RelationshipViewContext
    ) {
        self.note = note
        self.controller = controller
        self.context = context
    }

    private struct WorkspaceConnectionRow: Identifiable {
        let note: WorkspaceCatalogNote
        let kind: ScholiumConnectionPresentation

        var id: String { "\(kind.rawValue):\(note.reference.id)" }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    documentAttentionSection
                    ZoteroSourceSection(
                        note: note,
                        currentVault: context.currentVault,
                        analysesVaultID: context.analysesVaultID,
                        catalog: context.catalog,
                        resolveSource: context.resolveZoteroSource,
                        openItem: context.openZoteroItem,
                        confirmItem: context.confirmZoteroItem,
                        didConfirmSource: context.didConfirmZoteroSource
                    )
                    RecommendedBibliographySection(
                        controller: controller.bibliography,
                        openAnalysis: { reference in
                            if let note = context.catalog?.notes.first(where: {
                                $0.reference.vaultID == reference.vaultID
                                    && $0.reference.relativePath == reference.relativePath
                            }) {
                                controller.requestOpen(note.reference)
                            }
                        },
                        openZoteroItem: context.openZoteroItem,
                        copyText: context.copyResearchText,
                        repairMethod: context.repairBibliographyMethod
                    )
                    workspaceConnectionsSection
                }
                .padding(12)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Document Attention

    private var documentAttentionItems: [AttentionQueueItem] {
        guard let vaultID = context.currentVault?.id,
              let items = context.catalog?.attention else { return [] }
        let matching = items.filter {
            $0.note.vaultID == vaultID && $0.note.relativePath == note.relativePath
        }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(matching)
    }

    @ViewBuilder
    private var documentAttentionSection: some View {
        if !documentAttentionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Attention", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(documentAttentionItems.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(documentAttentionItems) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: attentionSymbol(item.kind))
                            .foregroundStyle(item.severity == .information ? Color.secondary : Color.orange)
                            .frame(width: 14)
                            .accessibilityHidden(true)

                        Button {
                            controller.requestOpen(item.note, sourceLine: item.locator?.line)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.kind.displayName)
                                    .font(.caption.weight(.medium))
                                Text(item.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let locator = item.locator {
                                    Text("Line \(locator.line)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open the exact source line when available")

                        Button {
                            dismissAttention(item)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Dismiss for \(attentionDismissalDurationText)")
                        .accessibilityLabel("Dismiss \(item.kind.displayName) for \(attentionDismissalDurationText)")
                    }
                }

                Text("Derived reminders only; they do not judge evidence or philosophical quality.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var attentionDismissalDurationText: String {
        let days = AttentionPreferences.normalizedDays(context.attentionDismissalDays)
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func dismissAttention(_ item: AttentionQueueItem) {
        var ledger = AttentionPreferences.decodeLedger(attentionDismissalLedgerData)
        ledger.removeExpired()
        ledger.dismiss(
            item,
            forDays: AttentionPreferences.normalizedDays(context.attentionDismissalDays)
        )
        attentionDismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func attentionSymbol(_ kind: AttentionQueueKind) -> String {
        switch kind {
        case .possibleOrphan: "circle.dashed"
        case .changedSinceReview: "clock.arrow.circlepath"
        case .malformedMetadata: "exclamationmark.braces"
        case .brokenConnection: "link"
        case .ambiguousConnection: "questionmark.diamond"
        case .unqualifiedAnalysisReliance: "exclamationmark.triangle"
        case .unresolvedIdentity: "person.text.rectangle"
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Research", systemImage: "books.vertical")
                .font(.headline)

            Text(note.title ?? note.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Triptych Connections

    private var workspaceConnectionsSection: some View {
        Group {
            if context.catalog == nil {
                loadingState
            } else if workspaceConnectionRows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Connections", systemImage: "link")
                        .font(.caption.weight(.semibold))
                    Text("No resolved Triptych connections were found for this note.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ScholiumConnectionPresentation.allCases) { kind in
                        let rows = workspaceConnectionRows.filter { $0.kind == kind }
                        if !rows.isEmpty {
                            workspaceConnectionGroup(kind: kind, rows: rows)
                        }
                    }
                }
            }
        }
    }

    private var workspaceConnectionRows: [WorkspaceConnectionRow] {
        guard let vaultID = context.currentVault?.id,
              let catalog = context.catalog,
              let graph = catalog.graph else { return [] }
        let current = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.notes.map {
            (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0)
        })
        var rows: [WorkspaceConnectionRow] = []

        for edge in graph.outgoing[current] ?? [] {
            guard let otherID = edge.destination?.note, let other = catalogByID[otherID] else { continue }
            rows.append(WorkspaceConnectionRow(
                note: other,
                kind: ScholiumConnectionPresentation(
                    vectorKind: edge.occurrence.vectorKind,
                    currentIsSource: true
                )
            ))
        }
        for edge in graph.incoming[current] ?? [] {
            guard let other = catalogByID[edge.source] else { continue }
            rows.append(WorkspaceConnectionRow(
                note: other,
                kind: ScholiumConnectionPresentation(
                    vectorKind: edge.occurrence.vectorKind,
                    currentIsSource: false
                )
            ))
        }

        return Dictionary(grouping: rows, by: \.id).compactMap { $0.value.first }.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.note.reference.vaultRole.rawValue != $1.note.reference.vaultRole.rawValue {
                return $0.note.reference.vaultRole.rawValue < $1.note.reference.vaultRole.rawValue
            }
            return $0.note.title.localizedStandardCompare($1.note.title) == .orderedAscending
        }
    }

    private func workspaceConnectionGroup(
        kind: ScholiumConnectionPresentation,
        rows: [WorkspaceConnectionRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .scholiumForeground(kind.colorRole)
                    .font(.caption)
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(rows.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        controller.requestOpen(row.note.reference)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: roleSymbol(row.note.reference.vaultRole))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.note.title)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(roleName(row.note.reference.vaultRole))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(row.note.reference.relativePath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(row.note.title) in \(roleName(row.note.reference.vaultRole))")
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func roleName(_ role: VaultRole) -> String {
        switch role {
        case .sourceCorpus: "Analyses"
        case .topicKnowledge: "Topics"
        case .dissertationControl, .draftProject: "Works"
        case .other: "Unclassified"
        }
    }

    private func roleSymbol(_ role: VaultRole) -> String {
        switch role {
        case .sourceCorpus: "doc.text"
        case .topicKnowledge: "lightbulb"
        case .dissertationControl, .draftProject: "pencil.and.outline"
        case .other: "tray"
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Analyzing relationships...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

}

private struct ZoteroSourceSection: View {
    let note: WindowDocumentLocation
    let currentVault: RegisteredVault?
    let analysesVaultID: UUID?
    let catalog: WorkspaceCatalogSnapshot?
    let resolveSource: (ZoteroSourceIdentity) async throws -> ZoteroMatchResult
    let openItem: (String) async -> Void
    let confirmItem: (String, VaultNoteReference) async throws -> Void
    let didConfirmSource: (String) -> Void

    private struct SourceRequest: Identifiable, Hashable {
        let reference: VaultNoteReference
        let referenceID: String
        let source: ZoteroSourceIdentity
        let fallbackTitle: String

        var id: String { referenceID + ":" + source.stableIdentity }
    }

    private struct PendingSelection: Identifiable {
        let request: SourceRequest
        let candidate: ZoteroItemMetadata
        let basis: ZoteroMatchBasis

        var id: String { request.id + ":" + candidate.key }
    }

    @State private var outcomes: [String: ZoteroMatchResult] = [:]
    @State private var stateText: String?
    @State private var isLoading = false
    @State private var showLinkedSources = false
    @State private var loadToken = UUID()
    @State private var pendingSelection: PendingSelection?

    private var requests: [SourceRequest] {
        guard let vault = currentVault else { return [] }

        if vault.role == .sourceCorpus {
            guard vault.id == analysesVaultID else {
                return []
            }
            let source = note.zoteroSourceIdentity
            let reference = VaultNoteReference(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                relativePath: note.relativePath
            )
            return [SourceRequest(
                reference: reference,
                referenceID: "\(vault.id.uuidString):\(note.relativePath)",
                source: source,
                fallbackTitle: note.title ?? note.displayName
            )]
        }

        guard [.topicKnowledge, .dissertationControl, .draftProject].contains(vault.role),
              let analysesVaultID,
              let catalog else { return [] }
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: note.relativePath
        )
        let selected = catalog.zoteroSourceAnalyses(
            linkedFrom: reference,
            analysesVaultID: analysesVaultID
        )
        let candidates: [SourceRequest] = selected.compactMap { candidate -> SourceRequest? in
            guard let source = candidate.zoteroSourceIdentity,
                  source.itemKey != nil else { return nil }
            return SourceRequest(
                reference: candidate.reference,
                referenceID: candidate.reference.id,
                source: source,
                fallbackTitle: candidate.title
            )
        }
        .sorted { $0.fallbackTitle.localizedStandardCompare($1.fallbackTitle) == .orderedAscending }
        return candidates
    }

    private var requestIdentity: String {
        requests.map(\.id).joined(separator: "|")
    }

    private var linkedSourcesLabel: String {
        switch currentVault?.role {
        case .topicKnowledge:
            "Analyses cited by this Topic (\(requests.count))"
        case .dissertationControl, .draftProject:
            "Analyses linked from this Work (\(requests.count))"
        default:
            "Linked Analyses (\(requests.count))"
        }
    }

    var body: some View {
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    requests.count == 1 && currentVault?.role == .sourceCorpus
                        ? "Zotero Source"
                        : "Zotero Sources from Linked Analyses",
                    systemImage: "books.vertical"
                )
                .font(.caption.weight(.semibold))

                if isLoading {
                    ProgressView("Checking Zotero…")
                        .controlSize(.small)
                } else if currentVault?.role == .sourceCorpus {
                    sourceRow(requests[0])
                } else {
                    DisclosureGroup(isExpanded: $showLinkedSources) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(requests) { request in
                                sourceRow(request)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(linkedSourcesLabel)
                            .font(.caption.weight(.medium))
                    }
                }

                if let stateText {
                    Label(stateText, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: requestIdentity) { await load() }
            .confirmationDialog(
                "Use This Zotero Item?",
                isPresented: Binding(
                    get: { pendingSelection != nil },
                    set: { if !$0 { pendingSelection = nil } }
                ),
                presenting: pendingSelection
            ) { selection in
                Button("Use for \(selection.request.fallbackTitle)") {
                    confirm(selection)
                }
                Button("Cancel", role: .cancel) { pendingSelection = nil }
            } message: { selection in
                Text("Scholium will store Zotero item \(selection.candidate.key) in the Analysis so future matches are stable. Zotero itself remains unchanged.")
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ request: SourceRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch outcomes[request.id] {
            case .matched(let citation, _):
                citationView(citation, showsExpandedMetadata: true)

            case .ambiguous(let candidates, let basis):
                Label(
                    "Multiple Zotero items match this Analysis. Confirm the correct item to make future matches stable.",
                    systemImage: "questionmark.diamond"
                )
                .font(.caption2)
                .foregroundStyle(.orange)

                ForEach(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 5) {
                        citationView(candidate, showsExpandedMetadata: false)
                        Button("Use This Zotero Item") {
                            pendingSelection = PendingSelection(
                                request: request,
                                candidate: candidate,
                                basis: basis
                            )
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Use \(candidate.title) for \(request.fallbackTitle)")
                    }
                        .padding(.leading, 8)
                }

            case .notFound:
                Text(request.fallbackTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                Label(
                    request.source.itemKey == nil
                        ? "No Zotero item matched by DOI or ISBN, citation key, or exact title, author, and year."
                        : "The Zotero item identified by this Analysis was not found.",
                    systemImage: "questionmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

            case .insufficientMetadata:
                Text(request.fallbackTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                Label(
                    "Add a Zotero item key, DOI or ISBN, citation key, or title, author, and year to identify this source.",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

            case nil:
                Text(request.fallbackTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func citationView(
        _ citation: ZoteroCitation,
        showsExpandedMetadata: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(citation.title)
                .font(.caption.weight(.medium))
                .lineLimit(3)

            let identity = [
                citation.formattedAuthors,
                citation.year.map(String.init),
            ].compactMap { $0 }.filter { !$0.isEmpty }
            if !identity.isEmpty {
                Text(identity.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            let publication = [
                citation.containerTitle,
                citation.volume.map { "vol. \($0)" },
                citation.issue.map { "no. \($0)" },
                citation.pages.map { "pp. \($0)" },
            ].compactMap { $0 }.filter { !$0.isEmpty }
            if !publication.isEmpty {
                Text(publication.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            metadataValue("DOI", citation.doi)
            metadataValue("ISBN", citation.isbn)
            metadataValue("Citation Key", citation.citationKey)

            if showsExpandedMetadata, hasExpandedMetadata(citation) {
                DisclosureGroup("More from Zotero") {
                    VStack(alignment: .leading, spacing: 5) {
                        metadataValue("Publisher", citation.publisher)
                        metadataValue("Edition", citation.edition)
                        metadataValue("URL", citation.url)
                        if !citation.collections.isEmpty {
                            metadataValue("Collections", citation.collections.joined(separator: ", "))
                        }
                        if let modified = citation.dateModified {
                            metadataValue(
                                "Modified in Zotero",
                                modified.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        if let abstract = citation.abstract {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Abstract")
                                    .font(.caption2.weight(.medium))
                                Text(abstract)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 3)
                }
                .font(.caption2)
            }

            Button("Open in Zotero") {
                Task { await openItem(citation.key) }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func metadataValue(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2)
        }
    }

    private func hasExpandedMetadata(_ citation: ZoteroCitation) -> Bool {
        citation.abstract != nil
            || citation.publisher != nil
            || citation.edition != nil
            || citation.url != nil
            || !citation.collections.isEmpty
            || citation.dateModified != nil
    }

    private func load() async {
        let token = UUID()
        loadToken = token
        let currentRequests = requests
        isLoading = true
        stateText = nil
        defer {
            if loadToken == token { isLoading = false }
        }

        var resolved: [String: ZoteroMatchResult] = [:]
        do {
            for request in currentRequests {
                guard !Task.isCancelled, loadToken == token else { return }
                resolved[request.id] = try await resolveSource(request.source)
            }
            guard !Task.isCancelled, loadToken == token else { return }
            outcomes = resolved
        } catch {
            guard !Task.isCancelled, loadToken == token else { return }
            outcomes = resolved
            stateText = error.localizedDescription
        }
    }

    private func confirm(_ selection: PendingSelection) {
        pendingSelection = nil
        Task {
            do {
                try await confirmItem(
                    selection.candidate.key,
                    selection.request.reference
                )
                outcomes[selection.request.id] = .matched(
                    selection.candidate,
                    basis: .itemKey
                )
                didConfirmSource(selection.request.fallbackTitle)
            } catch {
                stateText = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RelationshipView(
        note: .unclassified(NoteDocument(
            relativePath: "topics/consciousness.md",
            rawContent: "---\ntitle: Consciousness\nstatus: developing\n---\n"
        )),
        controller: ResearchController(),
        context: RelationshipViewContext(
            currentVault: nil,
            analysesVaultID: nil,
            catalog: nil,
            attentionDismissalDays: 7,
            resolveZoteroSource: { _ in .insufficientMetadata },
            openZoteroItem: { _ in },
            confirmZoteroItem: { _, _ in },
            didConfirmZoteroSource: { _ in },
            copyResearchText: { _ in },
            repairBibliographyMethod: {}
        )
    )
}
