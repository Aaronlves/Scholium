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
    let zoteroBinding: AnalysisZoteroBinding?
    let stableNoteID: UUID?
}

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let attentionPopoverSession: AttentionPopoverSession?
    let openProperties: () -> Void
    let openAttention: () -> Void
    let retryRefresh: () -> Void
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
    var zoteroBinding: AnalysisZoteroBinding? { presentation.zoteroBinding }
    var stableNoteID: UUID? { presentation.stableNoteID }
}

/// Document-local research context. Authoritative note content remains the
/// primary interface object; About is a compact projection and never a second
/// source of truth.
struct ResearchOverviewView: View {
    let note: WindowDocumentLocation
    let context: ResearchInspectorContentContext

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
                actionLabel: "Edit Metadata",
                systemImage: "slider.horizontal.3",
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
                            if !group.facts.isEmpty {
                                ScholiumApparatusFactGrid(facts: group.facts)
                            }
                            ForEach(Array(group.readingBlocks.enumerated()), id: \.offset) { _, block in
                                ScholiumApparatusReadingBlock(
                                    label: block.label,
                                    text: block.text
                                )
                            }
                            if !group.tags.isEmpty {
                                AboutTagsView(tags: group.tags)
                            }
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
    }

    private struct ReadingBlock {
        let label: String
        let text: String
    }

    private struct AboutGroupContent: Identifiable {
        var id: PropertyPresentationGroup { group }
        let group: PropertyPresentationGroup
        let facts: [ScholiumApparatusFact]
        let readingBlocks: [ReadingBlock]
        let tags: [String]
    }

    private var aboutGroups: [AboutGroupContent] {
        AboutProfileCatalog.groupedEntries(
            for: note.schemaProfile,
            visibleFields: context.aboutConfiguration?.visibleFields,
            catalog: context.metadataCatalog
        ).compactMap { configured in
            let facts = configured.keys.compactMap { key in
                isLongResearchField(key) || key == "keywords" ? nil : propertyFact(for: key)
            }
            let blocks = configured.keys.flatMap(readingBlocks(for:))
            let tags = configured.group == .authoredYAML
                && configured.keys.contains("keywords") ? note.tags : []
            guard !facts.isEmpty || !blocks.isEmpty || !tags.isEmpty else { return nil }
            return AboutGroupContent(
                group: configured.group,
                facts: facts,
                readingBlocks: blocks,
                tags: tags
            )
        }
    }

    private func propertyFact(for key: String) -> ScholiumApparatusFact? {
        let isManaged = context.metadataCatalog.contract(
            for: key,
            profile: note.schemaProfile
        ) != nil
        guard let raw = isManaged
            ? note.managedMetadataValue(named: key)
            : note.authoredYAMLValue(named: key) else { return nil }
        let value: String
        if !isManaged,
           case .string = raw,
           let token = note.authoredTopLevelScalarToken(named: key),
           FrontmatterPatchPlanner.isTimestampScalarToken(token) {
            value = token
        } else {
            guard let displayValue = propertyDisplayValue(raw, key: key) else { return nil }
            value = displayValue
        }
        let label = PropertyPresentationCatalog.presentation(
            for: key,
            in: note.schemaProfile,
            catalog: context.metadataCatalog
        )?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        return ScholiumApparatusFact(id: key, label: label, value: value)
    }

    private func readingBlocks(for key: String) -> [ReadingBlock] {
        let isManaged = context.metadataCatalog.contract(
            for: key,
            profile: note.schemaProfile
        ) != nil
        guard isLongResearchField(key),
              let value = isManaged
                ? note.managedMetadataValue(named: key)
                : note.authoredYAMLValue(named: key) else { return [] }
        let label = PropertyPresentationCatalog.presentation(
            for: key,
            in: note.schemaProfile,
            catalog: context.metadataCatalog
        )?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        switch value {
        case .string(let text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [ReadingBlock(label: label, text: text)]
        case .array:
            let values = value.canonicalStringList ?? []
            return values.enumerated().map { index, text in
                ReadingBlock(
                    label: values.count == 1 ? label : "\(label) \(index + 1)",
                    text: text
                )
            }
        default:
            return []
        }
    }

    private func isLongResearchField(_ key: String) -> Bool {
        if key == "summary" { return true }
        return context.metadataCatalog.contract(
            for: key,
            profile: note.schemaProfile
        )?.valueKind == .multilineText
    }

    private func propertyDisplayValue(_ value: YAMLValue, key: String) -> String? {
        let display: String? = switch value {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        case .array:
            value.canonicalStringList?.joined(separator: ", ")
                ?? PropertyContractCatalog.creatorNames(from: value)?
                    .map(\.displayName).joined(separator: "; ")
        case .object, .null:
            nil
        }
        guard let display else { return nil }
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private struct AboutTagsView: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: ScholiumMetrics.Properties.optionSpacing) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                ScholiumTagCapsuleLabel(tag)
                    .accessibilityLabel(tag)
            }
        }
        .accessibilityElement(children: .contain)
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
                zoteroBinding: nil,
                stableNoteID: nil
            ),
            attentionPopoverSession: nil,
            openProperties: {},
            openAttention: {},
            retryRefresh: {},
            openZoteroItem: { _ in },
            refreshZoteroMetadata: { _, _ in },
            manageZoteroBinding: { _, _ in }
        )
    )
    .frame(width: 320, height: 620)
}
