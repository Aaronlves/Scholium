import ScholiumContracts
#if DEBUG
import SwiftUI

private struct ScholiumComponentCatalog: View {
    enum Scenario: String {
        case ready = "Ready"
        case empty = "Empty"
        case loading = "Loading"
        case error = "Error"
        case conflict = "Conflict"
        case longText = "Long Text"
    }

    let scenario: Scenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScholiumPanelHeader("Research Inspector", subtitle: scenario.rawValue)
                scenarioContent
            }
            .padding(24)
        }
        .frame(width: 520, height: 620)
        .scholiumSurface(.document)
    }

    @ViewBuilder
    private var scenarioContent: some View {
        switch scenario {
        case .ready:
            ScholiumInlineStatus("Index Current", detail: "All projections match the committed revision.", kind: .confirmed)
            sourceAndNoteRows
        case .empty:
            ScholiumEmptyState(
                title: "No Matching Notes",
                detail: "No title, path, or alias matches this query.",
                systemImage: "doc.text.magnifyingglass"
            )
        case .loading:
            ProgressView("Preparing the Triptych catalog…")
                .frame(maxWidth: .infinity, minHeight: 180)
        case .error:
            ScholiumInlineStatus(
                "Search Unavailable",
                detail: "The existing results remain unchanged. Retry when the index is available.",
                kind: .destructive
            )
        case .conflict:
            ScholiumInlineStatus(
                "This Note Changed on Disk",
                detail: "The editor buffer is preserved for comparison or recovery.",
                kind: .attention
            )
        case .longText:
            ScholiumInlineStatus(
                "A deliberately long status that verifies wrapping without truncating the researcher-visible recovery explanation",
                detail: "This deterministic preview includes mixed-language content 关于注意与显著性 and a long path so localization, text scaling, and narrow layouts remain inspectable.",
                kind: .agentAuthorship
            )
            sourceAndNoteRows
        }
    }

    private var sourceAndNoteRows: some View {
        Group {
            ScholiumSourceAnchorRow(
                title: "Attention and perceptual salience",
                location: "Analysis.md, line 42",
                detail: "Explicit support Connection",
                action: {}
            )
            ScholiumNoteRow(
                title: "A deliberately long mixed-language note title 关于注意与显著性",
                role: "Analysis",
                location: "Sources/Attention/Example.md",
                symbol: "doc.text"
            )
        }
    }
}

private struct LifecycleDestinationCatalog: View {
    enum Scenario: Equatable {
        case populated
        case loading
        case empty
        case error
        case longTitle
        case chinese
    }

    let scenario: Scenario

    var body: some View {
        SidebarLifecycleDestinationView(
            scope: scenario == .chinese ? .setAside : .trash,
            items: items,
            isLoading: scenario == .loading,
            errorMessage: scenario == .error ? "The lifecycle listing is temporarily unavailable." : nil,
            requestedPutBackFocusPath: nil,
            onFocusRequestHandled: {},
            onRequestPutBackFocus: { _ in },
            onReload: {},
            onOpen: { _ in },
            onPutBack: { _ in },
            onReveal: { _ in },
            onMoveToTrash: { _ in },
            onDeletePermanently: { _ in }
        )
        .padding(.horizontal, ScholiumMetrics.Library.contentInset)
        .frame(width: 300, height: 380, alignment: .topLeading)
        .scholiumSurface(.navigation)
    }

    private var items: [LifecycleLocationItem] {
        switch scenario {
        case .loading, .empty, .error:
            []
        case .populated:
            [
                item(path: "Trash/Topics/Agency.md", title: "Agency"),
                item(path: "Trash/Analyses/Attention.md", title: "Attention and Salience"),
            ]
        case .longTitle:
            [
                item(
                    path: "Trash/Topics/Long Title.md",
                    title: "A deliberately long lifecycle title that must truncate before the Put Back action"
                ),
            ]
        case .chinese:
            [
                item(path: "Set Aside/Topics/注意与显著性.md", title: "关于注意、显著性与规范理由的长标题"),
                item(path: "Set Aside/Works/第三章.md", title: "第三章：拟议论证结构"),
            ]
        }
    }

    private func item(path: String, title: String) -> LifecycleLocationItem {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let document = NoteDocument(
            relativePath: path,
            rawContent: "---\ntitle: \"\(escapedTitle)\"\n---\n"
        )
        return LifecycleLocationItem(
            note: .unclassified(document),
            revision: document.fingerprint,
            noteID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
    }
}

/// Native design-only comparison for the D-102 Inspector typography. It uses
/// real research-density examples but owns no product state or behavior.
private struct PropertiesTypographyComparisonBoard: View {
    let panelWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            PropertiesTypographySample(
                treatment: .editorialHybrid,
                width: panelWidth
            )
            PropertiesTypographySample(
                treatment: .allSerif,
                width: panelWidth
            )
        }
        .padding(20)
        .scholiumSurface(.document)
    }
}

private struct PropertiesTypographySample: View {
    enum Treatment: String {
        case editorialHybrid = "Editorial hybrid"
        case allSerif = "All Serif"
    }

    let treatment: Treatment
    let width: CGFloat

    private var usesHybrid: Bool { treatment == .editorialHybrid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: treatment.rawValue)
                    .font(usesHybrid
                        ? ScholiumInterfaceTypography.rowTitle
                        : ScholiumTypography.swiftUIReadingFont(
                            size: 13,
                            relativeTo: .body,
                            bold: true
                        ))
                Text(verbatim: width == 320 ? "320 pt" : "Narrow width")
                    .font(usesHybrid
                        ? ScholiumInterfaceTypography.metadata
                        : ScholiumTypography.swiftUIReadingFont(
                            size: 11,
                            relativeTo: .caption
                        ))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
            .padding(.vertical, ScholiumGrid.Spacing.nestedContentInset)

            ScholiumStructuralRule()

            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    sampleSection("NEEDS ATTENTION", count: "0") {
                        EmptyView()
                    }

                    sampleSection("ANALYSIS ABOUT") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.readingBlockSpacing) {
                            shortFacts([
                                .init(id: "completion", label: "Completion", value: "6/11"),
                                .init(id: "authors", label: "Authors", value: "María Zambrano; 李明"),
                                .init(id: "year", label: "Year", value: "2024"),
                                .init(id: "type", label: "Type", value: "Edited collection"),
                            ])
                            readingBlock(
                                "Limitation",
                                "Only the English translation and Chapters 1–6 were consulted; the archival appendix remains unavailable."
                            )
                            readingBlock(
                                "Limitation",
                                "“Abstract”, tags, and Collections are bibliographic metadata, not evidence for the source's argument."
                            )
                            action(
                                "Edit Properties",
                                symbol: "slider.horizontal.3",
                                detail: nil
                            )
                        }
                    }

                    sampleSection("WORK ABOUT") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.readingBlockSpacing) {
                            readingBlock(
                                "Research Scope",
                                "Whether fittingness reasons alter a researcher's practical option-space without collapsing into a generic value-ranking thesis."
                            )
                            readingBlock(
                                "Limitation",
                                "The current note brackets the historical genealogy and addresses only the contemporary objection."
                            )
                            shortFacts([
                                .init(id: "kind", label: "Kind", value: "Dissertation chapter"),
                                .init(id: "venue", label: "Venue", value: "Doctoral dissertation / 博士论文"),
                            ])
                        }
                    }

                    sampleSection("CONNECT") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                            countedSubheading("RELATED SOURCES", count: "0")
                            countedSubheading("RELATED TOPICS", count: "0")
                            countedSubheading("NEIGHBOR WORKS", count: "0")
                        }
                    }

                    sampleSection("WORK WITH AGENT") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                            action(
                                "Discuss",
                                symbol: "bubble.left.and.bubble.right",
                                detail: "Reflect without changing the note."
                            )
                            action(
                                "Write",
                                symbol: "square.and.pencil",
                                detail: "Prepare one bounded Revise activity."
                            )
                        }
                    }

                    sampleSection("OTHER ACTIONS") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                            action(
                                "Check Fidelity",
                                symbol: "checkmark.seal",
                                detail: "Save the current edit before preparing this check.",
                                enabled: false
                            )
                            action(
                                "Open Research Record",
                                symbol: "clock.arrow.circlepath",
                                detail: nil
                            )
                        }
                    }

                    sampleSection("RESEARCH ACTIVITY", count: "0") {
                        EmptyView()
                    }
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
            }
        }
        .frame(width: width, height: 860, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .scholiumBoundary(.subtleBoundary, in: Rectangle())
    }

    private func sampleSection<Content: View>(
        _ title: String,
        count: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionContentSpacing) {
            HStack(alignment: .firstTextBaseline) {
                heading(title)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                if let count {
                    Text(verbatim: count)
                        .font(countFont.monospacedDigit())
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
            }
            content()
        }
    }

    @ViewBuilder
    private func heading(_ title: String) -> some View {
        if usesHybrid {
            Text(verbatim: title).scholiumApparatusHeadingStyle()
        } else {
            Text(verbatim: title)
                .font(ScholiumTypography.swiftUIReadingFont(
                    size: 10,
                    relativeTo: .caption,
                    bold: true
                ))
                .tracking(0.7)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
    }

    private var countFont: Font {
        usesHybrid
            ? ScholiumInterfaceTypography.metadata
            : ScholiumTypography.swiftUIReadingFont(size: 11, relativeTo: .caption)
    }

    @ViewBuilder
    private func shortFacts(_ facts: [ScholiumApparatusFact]) -> some View {
        if usesHybrid {
            ScholiumApparatusFactGrid(facts: facts)
        } else {
            VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.rowSpacing) {
                ForEach(facts) { fact in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            serifLabel(fact.label)
                            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                            serifValue(fact.value)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            serifLabel(fact.label)
                            serifValue(fact.value)
                                .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func readingBlock(_ label: String, _ text: String) -> some View {
        if usesHybrid {
            ScholiumApparatusReadingBlock(label: label, text: text)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                serifLabel(label)
                serifValue(text)
                    .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
            }
        }
    }

    private func countedSubheading(_ title: String, count: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            heading(title)
            Spacer()
            Text(verbatim: count)
                .font(countFont.monospacedDigit())
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
    }

    @ViewBuilder
    private func action(
        _ title: LocalizedStringResource,
        symbol: String,
        detail: String?,
        enabled: Bool = true
    ) -> some View {
        if usesHybrid {
            ScholiumApparatusActionButton(
                title,
                systemImage: symbol,
                detail: detail,
                action: {}
            )
            .disabled(!enabled)
        } else {
            Button(action: {}) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(ScholiumTypography.swiftUIReadingFont(
                                size: 12,
                                relativeTo: .body,
                                bold: true
                            ))
                        if let detail {
                            serifValue(detail)
                                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }

    private func serifLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(ScholiumTypography.swiftUIReadingFont(
                size: 12,
                relativeTo: .body,
                bold: true
            ))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
    }

    private func serifValue(_ text: String) -> some View {
        Text(verbatim: text)
            .font(ScholiumTypography.swiftUIReadingFont(size: 12, relativeTo: .body))
            .foregroundStyle(ScholiumColorRole.primaryText.color)
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ScholiumMonoComparison: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(verbatim: "Monospace A/B Proof")
                    .font(.title2.weight(.semibold))
                Text(verbatim: "Production Victor Mono beside the macOS system monospace. Review at normal and 200% document text sizes.")
                    .foregroundStyle(.secondary)

                MonoComparisonScaleSection(title: "100%", scale: 1)
                MonoComparisonScaleSection(title: "200%", scale: 2)
            }
            .padding(24)
        }
        .frame(width: 920, height: 760)
        .scholiumSurface(.document)
    }
}

private struct MonoComparisonScaleSection: View {
    let title: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ScholiumInterfaceTypography.sectionTitle)
            HStack(alignment: .top, spacing: 16) {
                MonoComparisonColumn(title: "Victor Mono", scale: scale, usesVictor: true)
                MonoComparisonColumn(title: "System Mono", scale: scale, usesVictor: false)
            }
        }
    }
}

private struct MonoComparisonColumn: View {
    let title: String
    let scale: CGFloat
    let usesVictor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(ScholiumInterfaceTypography.rowTitle)
            sample("Source", text: "research_unit:\n  completion: \"6/11\"", size: 14)
            sample("Code", text: "let claim = evidence.map(\\.source)", size: 13)
            sample("Diff", text: "+ Explicit premise\n− Unsupported inference", size: 13)
            sample("Revision", text: "c7f81d9a, 1,284 bytes", size: 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scholiumBoundary(
            .subtleBoundary,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func sample(_ label: String, text: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(.secondary)
            Text(text)
                .font(usesVictor
                    ? ScholiumTypography.swiftUIMonospaceFont(
                        size: size * scale,
                        relativeTo: .body
                    )
                    : .system(size: size * scale, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct ScholarlyEditorialWorkspaceSlice: View {
    let width: CGFloat

    private var sidebarWidth: CGFloat { width < 1_000 ? 210 : 250 }
    private var inspectorWidth: CGFloat { width < 1_080 ? 230 : 280 }

    var body: some View {
        HStack(spacing: 0) {
            editorialSidebar
                .frame(width: sidebarWidth)

            editorialDocument
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            editorialInspector
                .frame(width: inspectorWidth)
        }
        .frame(width: width, height: 760)
        .scholiumSurface(.document)
    }

    private var editorialSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Scholium")
                .font(ScholiumInterfaceTypography.identity)
            Text(verbatim: "Triptych — Immediate Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 0) {
                roleSegment("Analyses", selected: true)
                roleSegment("Topics", selected: false)
                roleSegment("Works", selected: false)
            }
            .padding(.top, 18)

            editorialLabel("LIBRARY")
                .padding(.top, 24)

            Label("On Immediate Results", systemImage: "folder")
                .font(ScholiumInterfaceTypography.rowTitle)
                .padding(.top, 10)

            VStack(spacing: 3) {
                previewNote("Preface", detail: "On the hunger for quick answers", selected: false)
                previewNote(
                    "I. The Seduction of Immediate Results",
                    detail: "Why we overvalue speed and mistake motion for progress.",
                    selected: true
                )
                previewNote("II. The Slow Interior", detail: "What cannot be seen cannot be hurried.", selected: false)
                previewNote("III. The Patient Practice", detail: "Discipline as a wager on unseen work.", selected: false)
            }
            .padding(.top, 8)

            Spacer()

            editorialLabel("TAGS")
            Text(verbatim: "attention, learning, uncertainty")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.navigation)
        .overlay(alignment: .trailing) { ScholiumStructuralRule(orientation: .vertical) }
    }

    private var editorialDocument: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Analyses", systemImage: "book")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: "/").foregroundStyle(.tertiary)
                Text(verbatim: "I. The Seduction of Immediate Results")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .overlay(alignment: .bottom) { ScholiumStructuralRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        Text(verbatim: "Analysis")
                            .font(ScholiumInterfaceTypography.editorialLabel)
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "Properties")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "6/11")
                            .font(.caption.weight(.medium).monospacedDigit())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .scholiumEditorialSurface(
                        .apparatus,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )

                    Text(verbatim: "I. The Seduction of Immediate Results")
                        .font(ScholiumInterfaceTypography.documentTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    ScholiumStructuralRule()

                    Text(verbatim: "Modern life trains us to expect visible results almost immediately. A message is delivered in seconds, but this speed quietly changes our sense of how long worthwhile work should take.")
                    Text(verbatim: "Serious learning does not obey this logic. Research advances through failed specifications, incomplete drafts, and conversations whose value becomes clear only months later.")
                    Text(verbatim: "哲学研究的进展并不总能立即显现。概念之间的张力、反例与修订，需要在缓慢而持续的阅读中逐渐成形。")
                }
                .font(ScholiumTypography.swiftUIReadingFont(size: 12, relativeTo: .body))
                .lineSpacing(5)
                .padding(.horizontal, width < 1_000 ? 28 : 52)
                .padding(.vertical, 26)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

        }
        .scholiumSurface(.document)
    }

    private var editorialInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(verbatim: "Overview")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                Text(verbatim: "Connections")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                    .foregroundStyle(.secondary)
                Text(verbatim: "Functions")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .overlay(alignment: .bottom) { ScholiumStructuralRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inspectorSection("LINKS TO THIS NOTE", count: "3")
                    inspectorLink("II. The Slow Interior")
                    inspectorLink("IV. Feedback and Delay")
                    inspectorLink("On Patience in Practice")

                    inspectorSection("ABOUT", count: nil)
                    inspectorFact("Completion", "6/11")
                    inspectorFact("Authors", "M. Example and 李明")
                    inspectorFact("Type", "Book")

                    inspectorSection("TAGS", count: "5")
                    Text(verbatim: "motivation  progress  feedback\nlearning  uncertainty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .overlay(alignment: .leading) { ScholiumStructuralRule(orientation: .vertical) }
    }

    private func roleSegment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                selected ? ScholiumColorRole.surfaceBackground.color : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private func previewNote(_ title: String, detail: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ScholiumInterfaceTypography.noteTitle)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? ScholiumColorRole.raisedSurfaceBackground.color : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(ScholiumColorRole.accent.color).frame(width: 3)
            }
        }
    }

    private func editorialLabel(_ title: String) -> some View {
        Text(title)
            .font(ScholiumInterfaceTypography.editorialLabel)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func inspectorSection(_ title: String, count: String?) -> some View {
        HStack {
            editorialLabel(title)
            Spacer()
            if let count { Text(count).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.top, 4)
    }

    private func inspectorLink(_ title: String) -> some View {
        Label(title, systemImage: "doc.text")
            .font(ScholiumInterfaceTypography.noteTitle)
            .lineLimit(2)
    }

    private func inspectorFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }
}

#Preview("Ready") {
    ScholiumComponentCatalog(scenario: .ready)
}

#Preview("Empty") {
    ScholiumComponentCatalog(scenario: .empty)
}

#Preview("Loading") {
    ScholiumComponentCatalog(scenario: .loading)
}

#Preview("Error") {
    ScholiumComponentCatalog(scenario: .error)
}

#Preview("Conflict") {
    ScholiumComponentCatalog(scenario: .conflict)
}

#Preview("Long Text - Dark") {
    ScholiumComponentCatalog(scenario: .longText)
        .preferredColorScheme(.dark)
}

#Preview("Increased Contrast") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(increasedContrast: true)
        )
}

#Preview("Reduced Transparency") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceTransparency: true)
        )
}

#Preview("Reduced Motion") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceMotion: true)
        )
}

#Preview("Lifecycle Destination — Populated") {
    LifecycleDestinationCatalog(scenario: .populated)
}

#Preview("Lifecycle Destination — Loading") {
    LifecycleDestinationCatalog(scenario: .loading)
}

#Preview("Lifecycle Destination — Empty") {
    LifecycleDestinationCatalog(scenario: .empty)
}

#Preview("Lifecycle Destination — Error") {
    LifecycleDestinationCatalog(scenario: .error)
}

#Preview("Lifecycle Destination — Long Title") {
    LifecycleDestinationCatalog(scenario: .longTitle)
}

#Preview("Lifecycle Destination — 简体中文") {
    LifecycleDestinationCatalog(scenario: .chinese)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Victor Mono vs System Mono") {
    ScholiumMonoComparison()
}

#endif
