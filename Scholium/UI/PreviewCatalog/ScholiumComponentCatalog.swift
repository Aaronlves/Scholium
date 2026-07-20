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
            sample("Source", text: "research_unit:\n  scope: fittingness", size: 14)
            sample("Code", text: "let claim = evidence.map(\\.source)", size: 13)
            sample("Diff", text: "+ Explicit premise\n− Unsupported inference", size: 13)
            sample("Revision", text: "c7f81d9a · 1,284 bytes", size: 11)
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
            Text(verbatim: "attention  ·  learning  ·  uncertainty")
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
                        Text(verbatim: "In Progress")
                            .font(.caption.weight(.medium))
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

                    inspectorSection("RESEARCH CONTEXT", count: nil)
                    inspectorFact("Status", "In Progress")
                    inspectorFact("Importance", "★★★★☆")
                    inspectorFact("Type", "Analysis")

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

#Preview("Victor Mono vs System Mono") {
    ScholiumMonoComparison()
}

#Preview("Scholarly Editorialism — 1380") {
    ScholarlyEditorialWorkspaceSlice(width: 1_380)
}

#Preview("Scholarly Editorialism — 1080") {
    ScholarlyEditorialWorkspaceSlice(width: 1_080)
}

#Preview("Scholarly Editorialism — 900") {
    ScholarlyEditorialWorkspaceSlice(width: 900)
}

#Preview("Scholarly Editorialism — Dark") {
    ScholarlyEditorialWorkspaceSlice(width: 1_080)
        .preferredColorScheme(.dark)
}
#endif
