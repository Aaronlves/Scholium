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
    let visibleAttentionItems: [AttentionQueueItem]
    let activityNotificationCount: Int
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

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let attentionPopoverSession: AttentionPopoverSession?
    let openProperties: () -> Void
    let openAttention: () -> Void
    let retryRefresh: () -> Void
    let saveManagedAboutField: @MainActor (
        WindowDocumentLocation,
        String,
        YAMLValue?
    ) async throws -> Void
    let saveAuthoredAboutField: @MainActor (
        WindowDocumentLocation,
        String,
        YAMLValue?
    ) async throws -> Void
    let openZoteroItem: (AnalysisZoteroBinding) async -> Void
    let refreshZoteroMetadata: (UUID, AnalysisZoteroBinding) -> Void
    let manageZoteroBinding: (UUID, AnalysisZoteroBinding?) -> Void

    var visibleAttentionItems: [AttentionQueueItem] { presentation.visibleAttentionItems }
    var notificationCount: Int {
        presentation.visibleAttentionItems.count
            + presentation.activityNotificationCount
    }
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
    @State private var activeAboutEditorKey: String?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionSpacing
            ) {
                attentionSection
                aboutSection
                ResearchProjectionFreshnessView(
                    freshness: context.freshness,
                    retry: context.retryRefresh
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

    private var attentionSection: some View {
        Button(action: context.openAttention) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
            ) {
                HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                    Image(systemName: "bell")
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .scholiumForeground(.attention)
                        .accessibilityHidden(true)
                    Text("NOTIFICATIONS")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .tracking(0.7)
                        .scholiumForeground(.attention)
                    Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                    Text(context.notificationCount.formatted())
                        .font(
                            ScholiumTypography.interface(.small, emphasis: .strong, tabularDigits: true)
                        )
                        .scholiumForeground(.attention)
                    Image(systemName: "chevron.forward")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.mutedText)
                        .accessibilityHidden(true)
                }

                if !visibleAttentionKinds.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
                    ) {
                        ForEach(
                            Array(visibleAttentionKinds.prefix(3)),
                            id: \.rawValue
                        ) { kind in
                            Text(attentionTitle(for: kind))
                                .font(ScholiumTypography.scholarly(.emphasis))
                                .scholiumForeground(.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .scholiumAttentionPopover(
            anchor: .inspector,
            session: context.attentionPopoverSession
        )
        .buttonStyle(ScholiumQuietRowButtonStyle(
            minimumHeight: ScholiumMetrics.Apparatus.actionRowMinimumHeight,
            verticalInset: ScholiumMetrics.Apparatus.actionRowVerticalInset
        ))
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .accessibilityLabel("Notifications")
        .accessibilityValue("\(context.notificationCount) items")
        .accessibilityIdentifier("scholium.researchOverview.notifications")
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScholiumApparatusSectionHeaderButton(
                aboutTitle,
                actionLabel: "Add Field",
                systemImage: "plus",
                accessibilityIdentifier: "scholium.about.edit",
                action: context.openProperties
            )
            .padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)

            VStack(
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(Array(aboutGroups.enumerated()), id: \.element.group) { index, group in
                    ScholiumPropertyGroup(
                        label: group.group.label,
                        separatesFromPrevious: index > 0
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumMetrics.Properties.fieldBlockSeparation
                        ) {
                            ForEach(group.fields) { field in
                                AboutEditablePropertyRow(
                                    descriptor: field,
                                    activeEditorKey: $activeAboutEditorKey,
                                    save: { value in
                                        switch field.authority {
                                        case .managedMetadata:
                                            try await context.saveManagedAboutField(
                                                note,
                                                field.key,
                                                value
                                            )
                                        case .authoredSource:
                                            try await context.saveAuthoredAboutField(
                                                note,
                                                field.key,
                                                value
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                ScholiumPropertyGroup(
                    label: String(localized: "File History"),
                    separatesFromPrevious: !aboutGroups.isEmpty
                ) {
                    ScholiumApparatusFactGrid(facts: fileHistoryFacts)
                }

                ScholiumPropertyGroup(
                    label: String(localized: "Settlement"),
                    separatesFromPrevious: true
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Properties.fieldBlockSeparation
                    ) {
                        ScholiumApparatusFactGrid(facts: settlementFacts)
                        if let rationale = context.settlement.rationale {
                            ScholiumApparatusReadingBlock(
                                label: String(localized: "Rationale"),
                                text: rationale
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .accessibilityIdentifier("scholium.about")

            if let binding = context.zoteroBinding {
                Button {
                    Task { await context.openZoteroItem(binding) }
                } label: {
                    ScholiumApparatusActionRowContent(
                        title: Text("Open in Zotero"),
                        systemImage: "arrow.up.forward.app",
                        showsChevron: false
                    )
                }
                .buttonStyle(ScholiumQuietRowButtonStyle(
                    minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    verticalInset: 0
                ))
                .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
                .padding(.top, ScholiumMetrics.Apparatus.sectionContentSpacing)
                .accessibilityIdentifier("scholium.researchOverview.openInZotero")

                if let noteID = context.stableNoteID {
                    Button {
                        context.refreshZoteroMetadata(noteID, binding)
                    } label: {
                        ScholiumApparatusActionRowContent(
                            title: Text("Refresh Zotero Metadata…"),
                            systemImage: "arrow.clockwise",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(ScholiumQuietRowButtonStyle(
                        minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                        verticalInset: 0
                    ))
                    .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityIdentifier(
                        "scholium.researchOverview.refreshZoteroMetadata"
                    )
                }
            }

            if let noteID = context.stableNoteID {
                Button {
                    context.manageZoteroBinding(noteID, context.zoteroBinding)
                } label: {
                    ScholiumApparatusActionRowContent(
                        title: Text(
                            context.zoteroBinding == nil
                                ? "Link Zotero Item…"
                                : "Manage Zotero Link…"
                        ),
                        systemImage: "link",
                        showsChevron: true
                    )
                }
                .buttonStyle(ScholiumQuietRowButtonStyle(
                    minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    verticalInset: 0
                ))
                .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
                .padding(.top, ScholiumMetrics.Apparatus.sectionContentSpacing)
                .accessibilityIdentifier("scholium.researchOverview.manageZoteroBinding")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: note.workspaceSnapshot?.stableIdentity.resolvedID) { _, _ in
            activeAboutEditorKey = nil
        }
    }

    private struct AboutGroupContent: Identifiable {
        var id: PropertyPresentationGroup { group }
        let group: PropertyPresentationGroup
        let fields: [AboutPropertyDescriptor]
    }

    private var aboutGroups: [AboutGroupContent] {
        AboutProfileCatalog.groupedEntries(
            for: note.schemaProfile,
            visibleFields: context.aboutConfiguration?.visibleFields,
            presentManagedFields: Set(note.managedMetadataFields.keys),
            catalog: context.metadataCatalog
        ).compactMap { configured in
            let fields = configured.keys.compactMap(propertyDescriptor(for:))
            guard !fields.isEmpty else { return nil }
            return AboutGroupContent(
                group: configured.group,
                fields: fields
            )
        }
    }

    private func propertyDescriptor(for key: String) -> AboutPropertyDescriptor? {
        guard let presentation = PropertyPresentationCatalog.presentation(
            for: key,
            in: note.schemaProfile,
            catalog: context.metadataCatalog
        ) else { return nil }
        if let contract = context.metadataCatalog.contract(
            for: key,
            profile: note.schemaProfile
        ) {
            return AboutPropertyDescriptor(
                presentation: presentation,
                contract: contract,
                authority: .managedMetadata,
                value: note.managedMetadataValue(named: key)
            )
        }
        guard let contract = PropertyContractCatalog.contract(
            for: key,
            profile: note.schemaProfile
        ) else { return nil }
        return AboutPropertyDescriptor(
            presentation: presentation,
            contract: contract,
            authority: .authoredSource,
            value: note.authoredYAMLValue(named: key)
        )
    }

    private var fileHistoryFacts: [ScholiumApparatusFact] {
        [
            ScholiumApparatusFact(
                id: "file-created",
                label: String(localized: "File Created"),
                value: formattedDate(note.workspaceSnapshot?.fileMetadata.creationDate),
                monospacedDigits: true
            ),
            ScholiumApparatusFact(
                id: "source-modified",
                label: String(localized: "Source Modified"),
                value: formattedDate(note.workspaceSnapshot?.fileMetadata.modificationDate),
                monospacedDigits: true
            ),
        ]
    }

    private var settlementFacts: [ScholiumApparatusFact] {
        var facts = [
            ScholiumApparatusFact(
                id: "settlement-status",
                label: String(localized: "Status"),
                value: settlementStatus
            ),
            ScholiumApparatusFact(
                id: "settled-at",
                label: context.settlement.state == .changedSinceSettlement
                    ? String(localized: "Last Settled")
                    : String(localized: "Settled"),
                value: context.settlement.settledAt.map(formattedDate) ?? String(localized: "Never"),
                monospacedDigits: true
            ),
        ]
        if let researcher = context.settlement.researcher, !researcher.isEmpty {
            facts.append(ScholiumApparatusFact(
                id: "settled-by",
                label: String(localized: "Researcher"),
                value: researcher
            ))
        }
        return facts
    }

    private var settlementStatus: String {
        switch context.settlement.state {
        case .settled: String(localized: "Settled")
        case .changedSinceSettlement: String(localized: "Changed since settlement")
        case .notYetSettled: String(localized: "Not yet settled")
        case .unavailable: String(localized: "Unavailable")
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return String(localized: "Unavailable") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func attentionTitle(for kind: AttentionQueueKind) -> LocalizedStringResource {
        switch kind {
        case .possibleOrphan: "Possible Orphan"
        case .synthesisMaterialChanged: "Synthesis Material Changed"
        case .malformedMetadata: "Malformed Metadata"
        case .brokenConnection: "Broken Connection"
        case .ambiguousConnection: "Ambiguous Connection"
        case .unresolvedIdentity: "Unresolved Identity"
        }
    }

    private var visibleAttentionKinds: [AttentionQueueKind] {
        var seen = Set<String>()
        return context.visibleAttentionItems.compactMap { item in
            seen.insert(item.kind.rawValue).inserted ? item.kind : nil
        }
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

#Preview {
    ResearchOverviewView(
        note: .syntheticPreview(
            relativePath: "topics/consciousness.md",
            rawContent: "# Consciousness\n",
            vaultRole: .topicKnowledge
        ),
        context: ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                visibleAttentionItems: [],
                activityNotificationCount: 0,
                freshness: .unavailable("No workspace is open."),
                aboutConfiguration: nil,
                metadataCatalog: .builtIn,
                settlement: .unavailable,
                zoteroBinding: nil,
                stableNoteID: nil
            ),
            attentionPopoverSession: nil,
            openProperties: {},
            openAttention: {},
            retryRefresh: {},
            saveManagedAboutField: { _, _, _ in },
            saveAuthoredAboutField: { _, _, _ in },
            openZoteroItem: { _ in },
            refreshZoteroMetadata: { _, _ in },
            manageZoteroBinding: { _, _ in }
        )
    )
    .frame(width: 320, height: 620)
}
