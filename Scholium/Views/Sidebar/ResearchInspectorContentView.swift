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
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
                    ) {
                        Text(freshness.titleResource)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = freshness.detail {
                            Text(detail)
                                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if freshness.permitsRetry {
                            ScholiumApparatusActionButton(
                                "Retry Refresh",
                                systemImage: "arrow.clockwise",
                                detail: "Rebuild derived state from the current saved source.",
                                action: retry
                            )
                        }
                    }
                }
                .accessibilityIdentifier("scholium.researchProjectionFreshness")
            }
        }
    }
}

struct ResearchOverviewPresentation {
    let researchUnit: ResearchUnitDeclaration
    let visibleAttentionItems: [AttentionQueueItem]
    let freshness: ResearchProjectionFreshness
    let propertiesConfiguration: VaultPropertiesConfiguration?
}

struct ResearchInspectorContentContext {
    let presentation: ResearchOverviewPresentation
    let openProperties: () -> Void
    let openAttention: () -> Void
    let retryRefresh: () -> Void

    var researchUnit: ResearchUnitDeclaration { presentation.researchUnit }
    var visibleAttentionItems: [AttentionQueueItem] { presentation.visibleAttentionItems }
    var freshness: ResearchProjectionFreshness { presentation.freshness }
    var propertiesConfiguration: VaultPropertiesConfiguration? {
        presentation.propertiesConfiguration
    }
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
                ResearchProjectionFreshnessBanner(
                    freshness: context.freshness,
                    retry: context.retryRefresh
                )
                attentionSection
                aboutSection
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
        ScholiumApparatusSection(
            "NEEDS ATTENTION",
            content: {
                if !context.visibleAttentionItems.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
                    ) {
                        ForEach(Array(context.visibleAttentionItems.prefix(3))) { item in
                            VStack(
                                alignment: .leading,
                                spacing: ScholiumMetrics.Apparatus.longTextLabelSpacing
                            ) {
                                Text(attentionTitle(for: item.kind))
                                    .font(ScholiumInterfaceTypography.apparatusBody.weight(.semibold))
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                Text(item.message)
                                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                                    .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
                            }
                        }
                        ScholiumApparatusActionButton(
                            "Show All",
                            systemImage: "exclamationmark.triangle",
                            detail: "Open the complete Attention queue.",
                            action: context.openAttention
                        )
                    }
                }
            },
            trailing: {
                Text(context.visibleAttentionItems.count.formatted())
                    .font(ScholiumInterfaceTypography.apparatusMetadata.monospacedDigit())
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
        )
        .accessibilityIdentifier("scholium.researchOverview.attention")
    }

    private var aboutSection: some View {
        ScholiumApparatusSection(aboutTitle) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
            ) {
                ForEach(Array(readingBlocks.enumerated()), id: \.offset) { _, block in
                    ScholiumApparatusReadingBlock(
                        label: block.label,
                        text: block.text,
                        monospacedDigits: block.monospacedDigits
                    )
                }

                if !propertyFacts.isEmpty {
                    ScholiumApparatusFactGrid(facts: propertyFacts)
                }

                ScholiumApparatusActionButton(
                    "Edit Properties",
                    systemImage: "slider.horizontal.3",
                    detail: nil,
                    action: context.openProperties
                )
                .accessibilityIdentifier("scholium.about.edit")
            }
        }
        .accessibilityIdentifier("scholium.about")
    }

    private struct ReadingBlock {
        let label: String
        let text: String
        var monospacedDigits = false
    }

    private var readingBlocks: [ReadingBlock] {
        switch context.researchUnit.state {
        case .absent:
            return []
        case .invalid(let message):
            return [ReadingBlock(
                label: ScholiumL10n.dynamicString("Research Unit"),
                text: message
            )]
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
        note: .unclassified(NoteDocument(
            relativePath: "topics/consciousness.md",
            rawContent: "# Consciousness\n"
        )),
        context: ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                researchUnit: ResearchUnitDeclaration(
                    frontmatter: [:],
                    profile: .topicMarkdown
                ),
                visibleAttentionItems: [],
                freshness: .unavailable("No workspace is open."),
                propertiesConfiguration: nil
            ),
            openProperties: {},
            openAttention: {},
            retryRefresh: {}
        )
    )
    .frame(width: 320, height: 620)
}
