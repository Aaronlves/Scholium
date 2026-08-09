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
    let researchUnit: ResearchUnitDeclaration
    let visibleAttentionItems: [AttentionQueueItem]
    let freshness: ResearchProjectionFreshness
    let propertiesConfiguration: VaultPropertiesConfiguration?
    let zoteroItemKey: String?
}

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let attentionPopoverSession: AttentionPopoverSession?
    let openProperties: () -> Void
    let openAttention: () -> Void
    let retryRefresh: () -> Void
    let openZoteroItem: (String) async -> Void

    var researchUnit: ResearchUnitDeclaration { presentation.researchUnit }
    var visibleAttentionItems: [AttentionQueueItem] { presentation.visibleAttentionItems }
    var freshness: ResearchProjectionFreshness { presentation.freshness }
    var propertiesConfiguration: VaultPropertiesConfiguration? {
        presentation.propertiesConfiguration
    }
    var zoteroItemKey: String? { presentation.zoteroItemKey }
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
                    Image(systemName: "exclamationmark.triangle")
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.attention.color)
                        .accessibilityHidden(true)
                    Text("NEEDS ATTENTION")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .tracking(0.7)
                        .foregroundStyle(ScholiumColorRole.attention.color)
                    Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                    Text(context.visibleAttentionItems.count.formatted())
                        .font(
                            ScholiumTypography.interface(.small, emphasis: .strong, tabularDigits: true)
                        )
                        .foregroundStyle(ScholiumColorRole.attention.color)
                    Image(systemName: "chevron.forward")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
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
                                .foregroundStyle(ScholiumColorRole.primaryText.color)
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
        .accessibilityLabel("Needs Attention")
        .accessibilityValue("\(context.visibleAttentionItems.count) items")
        .accessibilityIdentifier("scholium.researchOverview.attention")
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScholiumApparatusSectionHeaderButton(
                aboutTitle,
                actionLabel: "Edit Properties",
                systemImage: "slider.horizontal.3",
                accessibilityIdentifier: "scholium.about.edit",
                action: context.openProperties
            )
            .padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)

            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
            ) {
                if !propertyFacts.isEmpty {
                    ScholiumApparatusFactGrid(facts: propertyFacts)
                }

                if let invalidResearchUnitMessage {
                    ScholiumApparatusStateView(
                        "Research Unit",
                        detail: invalidResearchUnitMessage,
                        systemImage: "exclamationmark.triangle",
                        density: .block
                    )
                }

                ForEach(Array(readingBlocks.enumerated()), id: \.offset) { _, block in
                    ScholiumApparatusReadingBlock(
                        label: block.label,
                        text: block.text,
                        monospacedDigits: block.monospacedDigits
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .accessibilityIdentifier("scholium.about")

            if let itemKey = context.zoteroItemKey {
                Button {
                    Task { await context.openZoteroItem(itemKey) }
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct ReadingBlock {
        let label: String
        let text: String
        var monospacedDigits = false
    }

    private var readingBlocks: [ReadingBlock] {
        switch context.researchUnit.state {
        case .absent, .invalid:
            return []
        case .declared:
            var result: [ReadingBlock] = []
            let entries = AboutProfileCatalog.entries(
                for: note.schemaProfile,
                visibleFields: context.propertiesConfiguration?.visibleFields
            )
            for entry in entries {
                switch entry {
                case .completion:
                    continue
                case .scope(let label):
                    if let scope = context.researchUnit.scope {
                        result.append(ReadingBlock(
                            label: ScholiumL10n.dynamicString(label),
                            text: scope
                        ))
                    }
                case .limitations:
                    for (index, limitation) in context.researchUnit.limitations.enumerated() {
                        let label = context.researchUnit.limitations.count == 1
                            ? ScholiumL10n.dynamicString("Limitation")
                            : String.localizedStringWithFormat(
                                ScholiumL10n.dynamicString("Limitation %lld"),
                                Int64(index + 1)
                            )
                        result.append(ReadingBlock(label: label, text: limitation))
                    }
                case .property, .sourceBasis:
                    continue
                }
            }
            return result
        }
    }

    private var invalidResearchUnitMessage: String? {
        guard case .invalid(let message) = context.researchUnit.state else {
            return nil
        }
        return message
    }

    private var propertyFacts: [ScholiumApparatusFact] {
        let entries = AboutProfileCatalog.entries(
            for: note.schemaProfile,
            visibleFields: context.propertiesConfiguration?.visibleFields
        )
        return entries.compactMap { entry in
            switch entry {
            case .completion:
                guard let completion = context.researchUnit.completion else { return nil }
                return ScholiumApparatusFact(
                    id: "completion",
                    label: ScholiumL10n.dynamicString("Completion"),
                    value: completionDisplayValue(completion),
                    monospacedDigits: true
                )
            case .property(let key):
                return propertyFact(for: key)
            case .sourceBasis:
                guard let value = sourceBasis else { return nil }
                return ScholiumApparatusFact(
                    id: "source_basis",
                    label: ScholiumL10n.dynamicString("Source basis"),
                    value: value
                )
            case .scope, .limitations:
                return nil
            }
        }
    }

    private func propertyFact(for key: String) -> ScholiumApparatusFact? {
        guard let raw = note.property(at: key),
              let value = propertyDisplayValue(raw, key: key) else { return nil }
        let label: String = switch key {
        case "authors": ScholiumL10n.dynamicString(
            note.authors.count == 1 ? "Author" : "Authors"
        )
        case "debate_importance": ScholiumL10n.dynamicString("Importance")
        default:
            PropertyPresentationCatalog.presentation(
                for: key,
                in: note.schemaProfile
            )?.label ?? key.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return ScholiumApparatusFact(id: key, label: label, value: value)
    }

    private var sourceBasis: String? {
        let components: [String] = [
            sourceBasisValue(key: "access", suffix: nil),
            sourceBasisValue(key: "text_reliability", suffix: "text"),
            sourceBasisValue(key: "locators", suffix: "locators"),
        ].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    private func sourceBasisValue(key: String, suffix: String?) -> String? {
        guard let raw = note.property(at: key),
              let value = propertyDisplayValue(raw, key: key) else { return nil }
        return suffix.map { "\(value) \($0)" } ?? value
    }

    private func propertyDisplayValue(_ value: YAMLValue, key: String) -> String? {
        let display = value.displayScalar
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        guard !display.isEmpty, display != "null" else { return nil }
        let localized = display.prefix(1).uppercased() + display.dropFirst()
        return key == "debate_importance" ? "\(localized) of 10" : localized
    }

    private func completionDisplayValue(_ completion: AnalysisCompletion) -> String {
        switch completion {
        case .complete: ScholiumL10n.dynamicString("Complete")
        case .incomplete: ScholiumL10n.dynamicString("Incomplete")
        case .represented: completion.yamlScalar
        }
    }

    private func attentionTitle(for kind: AttentionQueueKind) -> LocalizedStringResource {
        switch kind {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceSettled: "Changed Since Settled"
        case .materialChangedSinceUse: "Material Changed Since Use"
        case .changeAttributionNeeded: "Change Attribution Needed"
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
                researchUnit: ResearchUnitDeclaration(
                    frontmatter: [:],
                    profile: .topicMarkdown
                ),
                visibleAttentionItems: [],
                freshness: .unavailable("No workspace is open."),
                propertiesConfiguration: nil,
                zoteroItemKey: nil
            ),
            attentionPopoverSession: nil,
            openProperties: {},
            openAttention: {},
            retryRefresh: {},
            openZoteroItem: { _ in }
        )
    )
    .frame(width: 320, height: 620)
}
