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
                self.identity == nextIdentity
            else { return }
            self.value = statistics
        }
    }
}
