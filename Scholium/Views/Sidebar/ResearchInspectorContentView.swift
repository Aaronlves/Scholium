import ScholiumContracts
import SwiftUI

// MARK: - Research Inspector content

enum ResearchProjectionFreshness: Equatable, Sendable {
    case refreshing
    case current
    case stale(String)
    case failed(String)
    case unavailable(String)

    var titleResource: LocalizedStringResource {
        switch self {
        case .refreshing: "Refreshing derived state…"
        case .current: "Current for saved source"
        case .stale: "Refresh Needed"
        case .failed: "Refresh Failed"
        case .unavailable: "Refresh Unavailable"
        }
    }

    var detail: String? {
        switch self {
        case .stale(let reason), .failed(let reason), .unavailable(let reason): reason
        case .refreshing, .current: nil
        }
    }

    var permitsRetry: Bool {
        switch self {
        case .stale, .failed: true
        case .refreshing, .current, .unavailable: false
        }
    }

    var isActionable: Bool {
        switch self {
        case .refreshing, .stale, .failed, .unavailable: true
        case .current: false
        }
    }
}

struct ResearchProjectionFreshnessBanner: View {
    let freshness: ResearchProjectionFreshness
    let retry: () -> Void

    var body: some View {
        Group {
            if freshness.isActionable {
                ScholiumApparatusSection("SOURCE FRESHNESS") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(freshness.titleResource)
                            .font(ScholiumInterfaceTypography.apparatusBody)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = freshness.detail {
                            Text(detail)
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if freshness.permitsRetry {
                            Button("Retry Refresh", action: retry)
                                .buttonStyle(.link)
                        }
                    }
                }
                .accessibilityIdentifier("scholium.researchProjectionFreshness")
            }
        }
    }
}

/// Immutable workspace context and app-only Zotero effects required by the
/// Research Inspector. Navigation remains a typed Research intent.
struct ResearchOverviewPresentation {
    let researchUnit: ResearchUnitDeclaration
    let currentVault: RegisteredVault?
    let analysesVaultID: UUID?
    let catalog: WorkspaceCatalogSnapshot?
    let visibleAttentionItems: [AttentionQueueItem]
    let freshness: ResearchProjectionFreshness
    let propertiesConfiguration: VaultPropertiesConfiguration?
}

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let openResearchRecord: () -> Void
    let openProperties: () -> Void
    let customizeProperties: () -> Void
    let openAttention: () -> Void
    let retryRefresh: () -> Void
    let resolveZoteroSource: (ZoteroSourceIdentity) async throws -> ZoteroMatchResult
    let openZoteroItem: (String) async -> Void
    let confirmZoteroItem: (String, VaultNoteReference) async throws -> Void
    let didConfirmZoteroSource: (String) -> Void

    var currentVault: RegisteredVault? { presentation.currentVault }
    var researchUnit: ResearchUnitDeclaration { presentation.researchUnit }
    var analysesVaultID: UUID? { presentation.analysesVaultID }
    var catalog: WorkspaceCatalogSnapshot? { presentation.catalog }
    var visibleAttentionItems: [AttentionQueueItem] { presentation.visibleAttentionItems }
    var freshness: ResearchProjectionFreshness { presentation.freshness }
    var propertiesConfiguration: VaultPropertiesConfiguration? {
        presentation.propertiesConfiguration
    }
}

/// Document-local research context: Attention, Zotero source identity, and
/// source-anchored Connections. Authoritative note content remains primary.
struct ResearchOverviewView: View {
    let note: WindowDocumentLocation
    let context: ResearchInspectorContentContext

    init(
        note: WindowDocumentLocation,
        context: ResearchInspectorContentContext
    ) {
        self.note = note
        self.context = context
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing
            ) {
                ResearchProjectionFreshnessBanner(
                    freshness: context.freshness,
                    retry: context.retryRefresh
                )
                attentionSection
                aboutSection
                ZoteroSourceSection(
                    note: note,
                    currentVault: context.currentVault,
                    analysesVaultID: context.analysesVaultID,
                    catalog: context.catalog,
                    compact: true,
                    resolveSource: context.resolveZoteroSource,
                    openItem: context.openZoteroItem,
                    confirmItem: context.confirmZoteroItem,
                    didConfirmSource: context.didConfirmZoteroSource
                )
            }
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
            .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
            .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Research sections

    private var aboutSection: some View {
        ScholiumApparatusSection(
            aboutTitle,
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.rowSpacing
                ) {
                    switch context.researchUnit.state {
                    case .absent:
                        Text("No Scope or Limitations have been declared.")
                            .foregroundStyle(.secondary)
                    case .declared:
                        if let scope = context.researchUnit.scope {
                            LabeledContent("Scope") {
                                Text(scope)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(
                            Array(context.researchUnit.limitations.enumerated()),
                            id: \.offset
                        ) { index, limitation in
                            LabeledContent(
                                context.researchUnit.limitations.count == 1
                                    ? "Limitation"
                                    : "Limitation \(index + 1)"
                            ) {
                                Text(limitation)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    case .invalid(let message):
                        Text(message)
                            .foregroundStyle(ScholiumColorRole.attention.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(priorityPropertyFacts) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(fact.label)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(fact.value)
                                .foregroundStyle(ScholiumColorRole.primaryText.color)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(ScholiumInterfaceTypography.apparatusBody)
                    }
                }
                .font(ScholiumInterfaceTypography.apparatusBody)
            },
            trailing: {
                HStack(spacing: 8) {
                    Button("Edit", action: context.openProperties)
                        .buttonStyle(.link)
                    Button("Customize", action: context.customizeProperties)
                        .buttonStyle(.link)
                }
            }
        )
        .accessibilityIdentifier("scholium.about")
    }

    private var attentionSection: some View {
        ScholiumApparatusSection("NEEDS ATTENTION") {
            if context.visibleAttentionItems.isEmpty {
                Text("No current research issues.")
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(context.visibleAttentionItems.prefix(3))) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attentionTitle(for: item.kind))
                                .font(ScholiumInterfaceTypography.apparatusBody.weight(.medium))
                            Text(item.message)
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Text("\(context.visibleAttentionItems.count) current issues")
                            .font(ScholiumInterfaceTypography.apparatusMetadata)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Show All", action: context.openAttention)
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .accessibilityIdentifier("scholium.researchOverview.attention")
    }

    private func attentionTitle(
        for kind: AttentionQueueKind
    ) -> LocalizedStringResource {
        switch kind {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceSettled: "Changed Since Settled"
        case .changeAttributionNeeded: "Change Attribution Needed"
        case .malformedMetadata: "Malformed Metadata"
        case .brokenConnection: "Broken Connection"
        case .ambiguousConnection: "Ambiguous Connection"
        case .unresolvedIdentity: "Unresolved Identity"
        }
    }

    private struct PropertyFact: Identifiable {
        let key: String
        let label: String
        let value: String
        var id: String { key }
    }

    private var priorityPropertyFacts: [PropertyFact] {
        let keys = context.propertiesConfiguration?.visibleFields
            ?? note.frontmatter.keys.sorted()

        return keys
            .filter {
                $0 != "title"
                    && $0 != "tags"
                    && $0 != "research_unit"
                    && $0 != "scope"
                    && $0 != "limitations"
                    && !ResearcherPropertyPolicy.isHidden($0)
            }
            .compactMap(propertyFact(for:))
    }

    private func propertyFact(for key: String) -> PropertyFact? {
        let value: String?
        if let raw = note.property(at: key) {
            value = propertyDisplayValue(raw, key: key)
        } else {
            value = nil
        }
        guard let value, !value.isEmpty else { return nil }

        let label: String
        switch key {
        case "authors": label = note.authors.count == 1 ? "Author" : "Authors"
        case "debate_importance": label = "Importance"
        default:
            label = PropertyPresentationCatalog.presentation(
                for: key,
                in: note.schemaProfile
            )?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return PropertyFact(key: key, label: label, value: value)
    }

    private func propertyDisplayValue(_ value: YAMLValue, key: String) -> String? {
        let display = value.displayScalar
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        guard !display.isEmpty, display != "null" else { return nil }
        return key == "debate_importance" ? "\(display) of 10" : display
    }

    private var aboutTitle: LocalizedStringResource {
        switch note.profile {
        case .paperAnalysis: "ABOUT THIS ANALYSIS"
        case .topicKnowledge: "ABOUT THIS TOPIC"
        case .draftProject: "ABOUT THIS WORK"
        case .generic: "ABOUT THIS NOTE"
        }
    }

}

private struct ZoteroSourceSection: View {
    let note: WindowDocumentLocation
    let currentVault: RegisteredVault?
    let analysesVaultID: UUID?
    let catalog: WorkspaceCatalogSnapshot?
    let compact: Bool
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

        guard [.topicKnowledge, .draftProject].contains(vault.role),
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
        case .draftProject:
            "Analyses linked from this Work (\(requests.count))"
        default:
            "Linked Analyses (\(requests.count))"
        }
    }

    var body: some View {
        if !requests.isEmpty {
            let sectionTitle: LocalizedStringResource = requests.count == 1
                && currentVault?.role == .sourceCorpus
                ? "ZOTERO SOURCE"
                : "ZOTERO SOURCES FROM LINKED ANALYSES"
            ScholiumApparatusSection(
                sectionTitle,
                showsDivider: false
            ) {
                if isLoading {
                    ScholiumApparatusRow(
                        leading: {
                            ProgressView()
                                .controlSize(.small)
                        },
                        content: {
                            Text("Checking Zotero…")
                                .font(ScholiumInterfaceTypography.apparatusBody)
                        }
                    )
                } else if compact, requests.count == 1 {
                    compactSourceRow(requests[0])
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
                    ScholiumApparatusRow(
                        leading: {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        },
                        content: {
                            Text(stateText)
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    )
                }
            }
            .accessibilityIdentifier("scholium.zoteroSourceSection")
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
    private func compactSourceRow(_ request: SourceRequest) -> some View {
        ScholiumApparatusRow(
            leading: {
                Image(systemName: "books.vertical")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            },
            content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source")
                        .font(ScholiumInterfaceTypography.apparatusBody)
                    if let compactSourceStatus = compactSourceStatus(for: request) {
                        Text(compactSourceStatus)
                            .font(ScholiumInterfaceTypography.apparatusMetadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            },
            trailing: {
                if case let .some(.matched(citation, _)) = outcomes[request.id] {
                    Button("Open in Zotero") {
                        Task { await openItem(citation.key) }
                    }
                    .buttonStyle(.link)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            compactSourceStatus(for: request)
                                ?? "Zotero source unavailable"
                        )
                }
            }
        )
    }

    private func compactSourceStatus(for request: SourceRequest) -> String? {
        if let stateText { return stateText }
        switch outcomes[request.id] {
        case .matched:
            return nil
        case .ambiguous:
            return "Multiple Zotero items match this Analysis."
        case .notFound:
            return request.source.itemKey == nil
                ? "No Zotero item matched by DOI or ISBN, citation key, or exact title, author, and year."
                : "The Zotero item identified by this Analysis was not found."
        case .insufficientMetadata:
            return "Add source metadata to identify this Zotero item."
        case nil:
            return isLoading ? "Checking Zotero…" : "Zotero source unavailable."
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
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
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
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
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
    ResearchOverviewView(
        note: .unclassified(NoteDocument(
            relativePath: "topics/consciousness.md",
            rawContent: "---\ntitle: Consciousness\nstatus: developing\n---\n"
        )),
        context: ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                researchUnit: ResearchUnitDeclaration(frontmatter: [:]),
                currentVault: nil,
                analysesVaultID: nil,
                catalog: nil,
                visibleAttentionItems: [],
                freshness: .unavailable("No workspace is open."),
                propertiesConfiguration: nil
            ),
            openResearchRecord: {},
            openProperties: {},
            customizeProperties: {},
            openAttention: {},
            retryRefresh: {},
            resolveZoteroSource: { _ in .insufficientMetadata },
            openZoteroItem: { _ in },
            confirmZoteroItem: { _, _ in },
            didConfirmZoteroSource: { _ in }
        )
    )
}
