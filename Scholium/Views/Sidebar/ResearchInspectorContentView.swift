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

struct ResearchProjectionFreshnessView: View {
    let freshness: ResearchProjectionFreshness
    let retry: () -> Void

    var body: some View {
        Group {
            if freshness.isActionable {
                ScholiumApparatusStateView(
                    freshness.titleResource,
                    detail: freshness.detail,
                    systemImage: systemImage,
                    showsProgress: freshness == .refreshing,
                    density: freshness.detail == nil ? .line : .block
                ) {
                    if freshness.permitsRetry {
                        Button("Retry", action: retry)
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                    }
                }
                .accessibilityIdentifier("scholium.researchProjectionFreshness")
            }
        }
    }

    private var systemImage: String {
        switch freshness {
        case .refreshing: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle"
        case .stale: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle"
        case .unavailable: "slash.circle"
        }
    }
}

struct ResearchOverviewPresentation {
    let notificationScope: VaultQualifiedNoteID?
    let freshness: ResearchProjectionFreshness
    let aboutConfiguration: VaultAboutConfiguration?
    let metadataCatalog: NoteMetadataCatalog
    let settlement: AboutSettlementPresentation
    let zoteroBinding: AnalysisZoteroBinding?
    let stableNoteID: UUID?
}

enum AboutSettlementState: Hashable, Sendable {
    case settled
    case changedSinceSettlement
    case notYetSettled
    case unavailable
}

struct AboutSettlementPresentation: Hashable, Sendable {
    let state: AboutSettlementState
    let settledAt: Date?
    let researcher: String?
    let rationale: String?

    static let unavailable = AboutSettlementPresentation(
        state: .unavailable,
        settledAt: nil,
        researcher: nil,
        rationale: nil
    )

    static func resolve(
        noteID: UUID?,
        currentRevision: DocumentFingerprint?,
        requirement: WorkspaceSettlementRequirement?,
        settlements: [SettlementRecord]
    ) -> AboutSettlementPresentation {
        guard let noteID, let currentRevision else { return .unavailable }
        let latest = requirement?.previousSettlement
            ?? settlements.filter { $0.noteID == noteID }
                .max { $0.settledAt < $1.settledAt }
        guard let latest else {
            return AboutSettlementPresentation(
                state: .notYetSettled,
                settledAt: nil,
                researcher: nil,
                rationale: nil
            )
        }
        let isCurrent = requirement == nil && latest.fingerprint == currentRevision
        return AboutSettlementPresentation(
            state: isCurrent ? .settled : .changedSinceSettlement,
            settledAt: latest.settledAt,
            researcher: latest.researcher,
            rationale: latest.rationale
        )
    }
}

/// Pure mapping from immutable source facts to the rows About presents. The
/// view supplies locale-aware date formatting; this type owns no file or
/// Settlement state.
enum AboutFactPresentation {
    static func fileHistory(
        metadata: WorkspaceFileMetadata?,
        formatDate: (Date?) -> String
    ) -> [ScholiumApparatusFact] {
        [
            ScholiumApparatusFact(
                id: "file-created",
                label: String(localized: "Created"),
                value: formatDate(metadata?.creationDate),
                monospacedDigits: true
            ),
            ScholiumApparatusFact(
                id: "source-modified",
                label: String(localized: "Modified"),
                value: formatDate(metadata?.modificationDate),
                monospacedDigits: true
            ),
        ]
    }

    static func settlement(
        _ settlement: AboutSettlementPresentation,
        formatDate: (Date?) -> String
    ) -> [ScholiumApparatusFact] {
        var facts = [
            ScholiumApparatusFact(
                id: "settlement-status",
                label: String(localized: "Settlement"),
                value: settlementStatus(settlement.state)
            ),
        ]
        if settlement.state == .settled
            || settlement.state == .changedSinceSettlement
        {
            facts.append(ScholiumApparatusFact(
                id: "settled-at",
                label: settlement.state == .changedSinceSettlement
                    ? String(localized: "Last Settled")
                    : String(localized: "Settled"),
                value: formatDate(settlement.settledAt),
                monospacedDigits: true
            ))
        }
        if let researcher = settlement.researcher, !researcher.isEmpty {
            facts.append(ScholiumApparatusFact(
                id: "settled-by",
                label: String(localized: "Researcher"),
                value: researcher
            ))
        }
        return facts
    }

    private static func settlementStatus(_ state: AboutSettlementState) -> String {
        switch state {
        case .settled: String(localized: "Settled")
        case .changedSinceSettlement: String(localized: "Changed since settlement")
        case .notYetSettled: String(localized: "Not yet settled")
        case .unavailable: String(localized: "Unavailable")
        }
    }
}

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let attentionPopoverSession: AttentionPopoverSession?
    let openAttention: () -> Void
    let retryRefresh: () -> Void
    let saveMetadata: @MainActor (WindowDocumentLocation, [String: YAMLValue], DocumentFingerprint?) async throws -> DocumentFingerprint?
    let registerMetadataFlush: (UUID, @escaping @MainActor () async throws -> Void) -> Void
    let unregisterMetadataFlush: (UUID) -> Void
    let reloadMetadata: @MainActor (WindowDocumentLocation) async throws -> (fields: [String: YAMLValue], revision: DocumentFingerprint?)
    let openZoteroItem: (AnalysisZoteroBinding) async -> Void
    let refreshZoteroMetadata: (UUID, AnalysisZoteroBinding) -> Void
    let manageZoteroBinding: (UUID, AnalysisZoteroBinding?) -> Void
    var attachments: ResearchAttachmentContext? = nil

    var freshness: ResearchProjectionFreshness { presentation.freshness }
    var aboutConfiguration: VaultAboutConfiguration? {
        presentation.aboutConfiguration
    }
    var metadataCatalog: NoteMetadataCatalog { presentation.metadataCatalog }
    var settlement: AboutSettlementPresentation { presentation.settlement }
    var zoteroBinding: AnalysisZoteroBinding? { presentation.zoteroBinding }
    var stableNoteID: UUID? { presentation.stableNoteID }
}

/// Document-local research context. Authoritative note content remains the
/// primary interface object; About is a compact projection and never a second
/// source of truth.
struct ResearchOverviewView: View {
    let note: WindowDocumentLocation
    let context: ResearchInspectorContentContext
    @State private var metadataHeight: CGFloat = 140
    @State private var metadataLabelWidth: CGFloat = OverviewFieldLayout.minimumLabelWidth
    @State private var fileInformationExpanded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(
                alignment: .leading,
                spacing: ResearchInspectorLayout.sectionSpacing
            ) {
                if let session = context.attentionPopoverSession,
                   let scope = context.presentation.notificationScope {
                    OverviewNotificationsView(session: session, scope: scope, open: context.openAttention)
                }
                aboutSection
                ResearchProjectionFreshnessView(
                    freshness: context.freshness,
                    retry: context.retryRefresh
                )
            }
            .padding(.horizontal, ResearchInspectorLayout.contentInset)
            .padding(.top, ResearchInspectorLayout.topInset)
            .padding(.bottom, ResearchInspectorLayout.bottomInset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverviewMetadataFields(
                note: note, catalog: context.metadataCatalog,
                visibleKeys: visibleMetadataKeys, context: context,
                measuredHeight: $metadataHeight, measuredLabelWidth: $metadataLabelWidth
            )
            .frame(height: metadataHeight)
            .accessibilityLabel("About Fields")

            if context.zoteroBinding != nil || context.stableNoteID != nil {
                Divider().padding(.vertical, 14)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Zotero").font(ScholiumTypography.interface(.control))
                    Spacer(minLength: 8)
                    Menu {
                        if let binding = context.zoteroBinding {
                            Button("Open in Zotero") { Task { await context.openZoteroItem(binding) } }
                            if let noteID = context.stableNoteID {
                                Button("Refresh Zotero Metadata…") { context.refreshZoteroMetadata(noteID, binding) }
                            }
                        }
                        if let noteID = context.stableNoteID {
                            Button(context.zoteroBinding == nil ? "Link Zotero Item…" : "Manage Zotero Link…") {
                                context.manageZoteroBinding(noteID, context.zoteroBinding)
                            }
                        }
                    } label: {
                        Text(context.zoteroBinding == nil ? "Link Item…" : "Linked")
                    }
                    .font(ScholiumTypography.interface(.control)).menuStyle(.button).buttonStyle(.accessoryBar).controlSize(.small)
                    .accessibilityLabel("Zotero Link")
                    .accessibilityIdentifier("scholium.researchOverview.manageZoteroBinding")
                }.frame(minHeight: 28)
            }
            if let attachments = context.attachments { OverviewAttachmentsView(context: attachments) }
            DisclosureGroup("File Information", isExpanded: $fileInformationExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(fileHistoryFacts + settlementFacts) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: OverviewFieldLayout.columnSpacing) {
                            Text(fact.label).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                                .frame(width: metadataLabelWidth, alignment: .trailing)
                            Text(fact.value).foregroundStyle(ScholiumNativeColorRole.label.color).textSelection(.enabled)
                                .padding(.leading, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: OverviewFieldLayout.rowHeight)
                    }
                    if let rationale = context.settlement.rationale {
                        Text(rationale).textSelection(.enabled).padding(.top, 6)
                    }
                }.padding(.top, 6)
            }
            .font(ScholiumTypography.interface(.control))
            .padding(.top, 20)
            .accessibilityIdentifier("scholium.overview.fileInformation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleMetadataKeys: [String] {
        AboutProfileCatalog.groupedEntries(
            for: note.schemaProfile,
            visibleFields: context.aboutConfiguration?.visibleFields,
            presentManagedFields: Set(note.managedMetadataFields.keys),
            catalog: context.metadataCatalog
        ).flatMap(\.keys)
    }

    private var fileHistoryFacts: [ScholiumApparatusFact] {
        AboutFactPresentation.fileHistory(
            metadata: note.workspaceSnapshot?.fileMetadata,
            formatDate: formattedDate
        )
    }

    private var settlementFacts: [ScholiumApparatusFact] {
        AboutFactPresentation.settlement(
            context.settlement,
            formatDate: formattedDate
        )
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return String(localized: "Unavailable") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }


}

#Preview {
    ResearchOverviewView(
        note: .syntheticPreview(
            relativePath: "topics/consciousness.md",
            rawContent: "# Consciousness\n",
            vaultRole: .topicKnowledge
        ),
        context: ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                notificationScope: nil,
                freshness: .unavailable("No workspace is open."),
                aboutConfiguration: nil,
                metadataCatalog: .builtIn,
                settlement: .unavailable,
                zoteroBinding: nil,
                stableNoteID: nil
            ),
            attentionPopoverSession: nil,
            openAttention: {},
            retryRefresh: {},
            saveMetadata: { _, _, _ in nil },
            registerMetadataFlush: { _, _ in },
            unregisterMetadataFlush: { _ in },
            reloadMetadata: { _ in ([:], nil) },
            openZoteroItem: { _ in },
            refreshZoteroMetadata: { _, _ in },
            manageZoteroBinding: { _, _ in }
        )
    )
    .frame(width: 320, height: 620)
}
