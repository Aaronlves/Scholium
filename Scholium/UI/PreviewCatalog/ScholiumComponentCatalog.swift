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
                Text("Monospace A/B Proof")
                    .font(.title2.weight(.semibold))
                Text("Production Victor Mono beside the macOS system monospace. Review at normal and 200% document text sizes.")
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
}

#Preview("Reduced Transparency") {
    ScholiumComponentCatalog(scenario: .ready)
}

#Preview("Reduced Motion") {
    ScholiumComponentCatalog(scenario: .ready)
}

#Preview("Victor Mono vs System Mono") {
    ScholiumMonoComparison()
}
#endif
