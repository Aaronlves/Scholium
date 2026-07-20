import ScholiumContracts
import SwiftUI

// MARK: - Research Inspector content

/// Immutable workspace context and app-only Zotero effects required by the
/// Research Inspector. Navigation remains a typed Research intent.
struct ResearchInspectorContentContext {
    let currentVault: RegisteredVault?
    let analysesVaultID: UUID?
    let catalog: WorkspaceCatalogSnapshot?
    let reviewDisplayState: HumanReviewDisplayState
    let reviewRecord: HumanReviewRecord?
    let currentRevision: DocumentFingerprint?
    let openReview: () -> Void
    let openResearchRecord: () -> Void
    let openProperties: () -> Void
    let resolveZoteroSource: (ZoteroSourceIdentity) async throws -> ZoteroMatchResult
    let openZoteroItem: (String) async -> Void
    let confirmZoteroItem: (String, VaultNoteReference) async throws -> Void
    let didConfirmZoteroSource: (String) -> Void
    let copyResearchText: (String) -> Void
    let repairBibliographyMethod: () -> Void
}

/// Document-local research context: Attention, Zotero source identity, and
/// source-anchored Connections. Authoritative note content remains primary.
struct ResearchInspectorContentView: View {
    let note: WindowDocumentLocation
    let context: ResearchInspectorContentContext
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

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
                reviewStatusSection
                propertiesSection
                provenanceSection
                diagnosticsSection
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

    private var reviewStatusSection: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                    Text("REVIEW STATUS")
                        .font(ScholiumInterfaceTypography.apparatusLabel)
                        .tracking(0.7)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)

                    if context.reviewRecord?.latestReview != nil {
                        HStack(spacing: 5) {
                            Image(systemName: reviewRevisionSymbol)
                                .font(.system(size: 6, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(reviewRevisionTitle)
                        }
                        .font(ScholiumInterfaceTypography.apparatusMetadata)
                        .foregroundStyle(reviewRevisionColor)
                        .accessibilityElement(children: .combine)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    reviewBadge

                    VStack(alignment: .leading, spacing: 1) {
                        Text(reviewTitle)
                            .font(ScholiumInterfaceTypography.reviewValue)
                            .foregroundStyle(ScholiumColorRole.primaryText.color)
                            .fixedSize(horizontal: false, vertical: true)

                        if let latest = context.reviewRecord?.latestReview {
                            Text("Reviewed \(latest.completedAt, style: .relative)")
                                .font(ScholiumInterfaceTypography.apparatusMetadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if let reviewNote = completedReviewNote {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(reviewColor)
                            .frame(width: 2)
                            .accessibilityHidden(true)

                        Text(reviewNote)
                            .font(ScholiumInterfaceTypography.reviewSummary)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                }

                ScholiumStructuralRule()

                HStack(spacing: 8) {
                    if let fingerprint = context.reviewRecord?.latestReview?.fingerprint.sha256 {
                        Text("Fingerprint \(fingerprint.prefix(4))…\(fingerprint.suffix(4))")
                            .font(ScholiumTypography.swiftUIRevisionIdentity())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button(reviewActionTitle, action: context.openReview)
                        .font(ScholiumInterfaceTypography.apparatusBody)
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .buttonStyle(.plain)
                        .frame(
                            minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget,
                            alignment: .trailing
                        )
                        .contentShape(Rectangle())
                }
            }
            .padding(12)
            .background(
                ScholiumColorRole.raisedSurfaceBackground.color.opacity(0.42),
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialPanelCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialPanelCornerRadius,
                    style: .continuous
                )
                .stroke(reviewColor.opacity(0.55), lineWidth: 1)
            }

            ScholiumStructuralRule()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewBadge: some View {
        ZStack {
            Circle()
                .fill(reviewBadgeIsFilled ? reviewColor : Color.clear)
            Circle()
                .stroke(reviewColor, lineWidth: 1.5)
            if let symbol = reviewBadgeForegroundSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        reviewBadgeIsFilled
                            ? ScholiumColorRole.documentBackground.color
                            : reviewColor
                    )
            }
        }
        .frame(width: 34, height: 34)
        .shadow(
            color: reviewBadgeIsFilled ? reviewColor.opacity(0.26) : .clear,
            radius: 5,
            x: 0,
            y: 2
        )
        .accessibilityHidden(true)
    }

    private var propertiesSection: some View {
        ScholiumApparatusSection(
            "PROPERTIES",
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.rowSpacing
                ) {
                    if priorityPropertyFacts.isEmpty {
                        Text("No priority properties")
                            .font(ScholiumInterfaceTypography.apparatusBody)
                            .foregroundStyle(.secondary)
                    } else {
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
                }
            },
            trailing: {
                Button(action: context.openProperties) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Open Properties")
                .accessibilityLabel("Open Properties")
            }
        )
    }

    private var provenanceSection: some View {
        ScholiumApparatusSection(
            "PROVENANCE",
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.rowSpacing
                ) {
                    provenanceRow(
                        symbol: "doc.text",
                        title: "Current note",
                        date: note.fileModifiedAt
                    )
                    if let review = context.reviewRecord?.latestReview {
                        provenanceRow(
                            symbol: "checkmark.seal",
                            title: "Human review",
                            date: review.completedAt
                        )
                    }
                }
            },
            trailing: {
                Button(action: context.openResearchRecord) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Open Research Record")
                .accessibilityLabel("Open Research Record")
            }
        )
    }

    private var diagnosticsSection: some View {
        ScholiumApparatusSection(
            "DIAGNOSTICS",
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.rowSpacing
                ) {
                    ForEach(diagnostics) { diagnostic in
                        ScholiumApparatusRow(
                            leading: {
                                Image(systemName: diagnostic.symbol)
                                    .foregroundStyle(diagnostic.color)
                                    .accessibilityHidden(true)
                            },
                            content: {
                                Text(diagnostic.title)
                                    .font(ScholiumInterfaceTypography.apparatusBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(diagnostic.title): \(diagnostic.accessibilityState)"
                        )
                    }
                }
            }
        )
    }

    private func provenanceRow(symbol: String, title: String, date: Date) -> some View {
        ScholiumApparatusRow(
            leading: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            },
            content: {
                Text(title)
                    .font(ScholiumInterfaceTypography.apparatusBody)
            },
            trailing: {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(ScholiumInterfaceTypography.apparatusMetadata)
                    .foregroundStyle(.secondary)
            }
        )
    }

    private var reviewTitle: String {
        if context.currentVault?.role.allowsHumanReview == false {
            return "Critique"
        }
        return switch context.reviewDisplayState {
        case .notReviewed:
            context.currentRevision != nil && context.reviewRecord?.latestReview != nil
                ? "Changed since review"
                : "Not reviewed"
        case .reviewed: "Reviewed"
        case .qualified: "Qualified"
        case .unqualified: "Unqualified"
        }
    }

    private var reviewActionTitle: String {
        context.currentVault?.role.allowsHumanReview == false ? "Open Critique" : "Open Review"
    }

    private var completedReviewNote: String? {
        guard let note = context.reviewRecord?.latestReview?.reviewNote,
              !note.isEmpty else { return nil }
        return note
    }

    private var latestReviewMatchesCurrentRevision: Bool {
        guard let latest = context.reviewRecord?.latestReview,
              let currentRevision = context.currentRevision else { return false }
        return latest.fingerprint == currentRevision
    }

    private var reviewRevisionTitle: String {
        guard context.currentVault?.role.allowsHumanReview != false else {
            return "Current note"
        }
        guard context.reviewRecord?.latestReview != nil else { return "Not reviewed" }
        return latestReviewMatchesCurrentRevision ? "Current revision" : "Earlier revision"
    }

    private var reviewRevisionSymbol: String {
        latestReviewMatchesCurrentRevision ? "circle.fill" : "circle"
    }

    private var reviewRevisionColor: Color {
        if latestReviewMatchesCurrentRevision {
            return ScholiumColorRole.confirmed.color
        }
        if context.reviewRecord?.latestReview != nil {
            return ScholiumColorRole.attention.color
        }
        return ScholiumColorRole.secondaryText.color
    }

    private var reviewBadgeIsFilled: Bool {
        context.reviewRecord?.latestReview != nil
            || context.reviewDisplayState != .notReviewed
    }

    private var reviewBadgeForegroundSymbol: String? {
        if context.reviewDisplayState == .notReviewed,
           context.reviewRecord?.latestReview == nil {
            return nil
        }
        return switch context.reviewDisplayState {
        case .notReviewed: "clock"
        case .reviewed, .qualified: "checkmark"
        case .unqualified: "xmark"
        }
    }

    private var reviewColor: Color {
        switch context.reviewDisplayState {
        case .notReviewed: ScholiumColorRole.mutedText.color
        case .reviewed: ScholiumColorRole.secondaryText.color
        case .qualified: ScholiumColorRole.confirmed.color
        case .unqualified: ScholiumColorRole.destructive.color
        }
    }

    private struct PropertyFact: Identifiable {
        let key: String
        let label: String
        let value: String
        var id: String { key }
    }

    private var priorityPropertyFacts: [PropertyFact] {
        let keys: [String] = switch note.profile {
        case .paperAnalysis:
            ["authors", "year", "type", "status", "debate_importance"]
        case .topicKnowledge:
            ["status", "research_unit.scope", "aliases"]
        case .draftProject:
            ["kind", "status", "research_unit.scope", "deadline", "authors"]
        case .generic:
            note.frontmatter.keys
                .filter {
                    $0 != "title" && $0 != "tags" && !ResearcherPropertyPolicy.isHidden($0)
                }
                .sorted()
        }

        return Array(keys.compactMap(propertyFact(for:)).prefix(5))
    }

    private func propertyFact(for key: String) -> PropertyFact? {
        let value: String?
        if key == "research_unit.scope" {
            value = note.researchUnit.scope
        } else if let raw = note.property(at: key) {
            value = propertyDisplayValue(raw, key: key)
        } else {
            value = nil
        }
        guard let value, !value.isEmpty else { return nil }

        let label: String
        switch key {
        case "authors": label = note.authors.count == 1 ? "Author" : "Authors"
        case "research_unit.scope": label = "Scope"
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

    private struct DiagnosticItem: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let color: Color
        let accessibilityState: String
    }

    private var diagnostics: [DiagnosticItem] {
        let malformed = documentAttentionItems.contains { $0.kind == .malformedMetadata }
        let broken = documentAttentionItems.contains {
            $0.kind == .brokenConnection || $0.kind == .ambiguousConnection
        }
        let unresolvedIdentity = documentAttentionItems.contains { $0.kind == .unresolvedIdentity }
        let catalogReady = context.catalog != nil
        return [
            diagnostic("source", "Source", passes: !note.rawContent.isEmpty),
            diagnostic("properties", "Properties", passes: catalogReady ? !malformed : nil),
            diagnostic("connections", "Connections", passes: catalogReady ? !broken : nil),
            diagnostic("identity", "Identity", passes: catalogReady ? !unresolvedIdentity : nil),
        ]
    }

    private func diagnostic(_ id: String, _ title: String, passes: Bool?) -> DiagnosticItem {
        let presentation: (String, Color, String) = switch passes {
        case true:
            ("checkmark.circle", ScholiumColorRole.confirmed.color, "No issue")
        case false:
            ("exclamationmark.circle", ScholiumColorRole.attention.color, "Needs attention")
        case nil:
            ("questionmark.circle", ScholiumColorRole.secondaryText.color, "Not yet checked")
        }
        return DiagnosticItem(
            id: id,
            title: title,
            symbol: presentation.0,
            color: presentation.1,
            accessibilityState: presentation.2
        )
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
            ScholiumApparatusSection(
                requests.count == 1 && currentVault?.role == .sourceCorpus
                    ? "ZOTERO SOURCE"
                    : "ZOTERO SOURCES FROM LINKED ANALYSES",
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
                Text("Source")
                    .font(ScholiumInterfaceTypography.apparatusBody)
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
                        .accessibilityLabel("Zotero source unavailable")
                }
            }
        )
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
    ResearchInspectorContentView(
        note: .unclassified(NoteDocument(
            relativePath: "topics/consciousness.md",
            rawContent: "---\ntitle: Consciousness\nstatus: developing\n---\n"
        )),
        context: ResearchInspectorContentContext(
            currentVault: nil,
            analysesVaultID: nil,
            catalog: nil,
            reviewDisplayState: .notReviewed,
            reviewRecord: nil,
            currentRevision: nil,
            openReview: {},
            openResearchRecord: {},
            openProperties: {},
            resolveZoteroSource: { _ in .insufficientMetadata },
            openZoteroItem: { _ in },
            confirmZoteroItem: { _, _ in },
            didConfirmZoteroSource: { _ in },
            copyResearchText: { _ in },
            repairBibliographyMethod: {}
        )
    )
}
