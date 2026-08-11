import ScholiumContracts
import SwiftUI

@MainActor
final class ReviewDocumentStatisticsModel: ObservableObject {
    @Published private(set) var value = DocumentStatistics.emptyBody

    private struct Identity: Equatable {
        let revision: String
        let selectionLowerBound: Int?
        let selectionUpperBound: Int?
        let fallbackSelection: String?
    }

    private var identity: Identity?
    private var task: Task<Void, Never>?

    func update(
        markdownSource: String,
        revision: String,
        selection: MarkdownReviewSelection?
    ) {
        let exactRange = selection?.exactUTF16Range
        let nextIdentity = Identity(
            revision: revision,
            selectionLowerBound: exactRange?.lowerBound,
            selectionUpperBound: exactRange?.upperBound,
            fallbackSelection: exactRange == nil ? selection?.excerpt : nil
        )
        guard nextIdentity != identity else { return }
        identity = nextIdentity
        task?.cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
            let statistics = await Task.detached(priority: .utility) {
                if let exactRange {
                    return DocumentStatisticsCalculator.calculate(
                        markdownSource: markdownSource,
                        selectedUTF16Ranges: [exactRange]
                    )
                }
                if let selection {
                    return DocumentStatisticsCalculator.calculateVisibleText(
                        selection.excerpt,
                        scope: .selection
                    )
                }
                return DocumentStatisticsCalculator.calculate(
                    markdownSource: markdownSource
                )
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.identity == nextIdentity else { return }
            self.value = statistics
        }
    }
}

enum DocumentStatisticsFormatter {
    static func accessibilityValue(_ statistics: DocumentStatistics) -> String {
        let scope = statistics.scope == .selection
            ? String(localized: "Selection statistics")
            : String(localized: "Body statistics")
        return String(
            localized: "\(scope). English words: \(statistics.englishWords). Chinese characters: \(statistics.chineseCharacters). Characters: \(statistics.characters).",
            table: "Localizable",
            bundle: .module
        )
    }
}

struct DocumentStatisticsStatus: View {
    let statistics: DocumentStatistics

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: ScholiumGrid.Spacing.regionContentInset)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    if statistics.scope == .selection {
                        Text("Selection")
                    }
                    Text("English \(statistics.englishWords)")
                    Text("Chinese \(statistics.chineseCharacters)")
                    Text("Characters \(statistics.characters)")
                }
                Text("Characters \(statistics.characters)")
            }
            .font(ScholiumTypography.interface(.small).monospacedDigit())
            .scholiumForeground(.mutedText)
            .lineLimit(1)
        }
        .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .background(ScholiumColorRole.documentBackground.color)
        .overlay(alignment: .top) { ScholiumStructuralRule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Document Statistics")
        .accessibilityValue(DocumentStatisticsFormatter.accessibilityValue(statistics))
        .accessibilityIdentifier("scholium.documentStatistics")
    }
}
