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
        .scholiumSurface(.surface)
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
#endif
