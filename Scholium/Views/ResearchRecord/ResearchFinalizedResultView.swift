import AppKit
import ScholiumContracts
import SwiftUI

struct ResearchFinalizedResultView: View {
    let record: PortableResearchRecord
    let context: ResearchRecordBrowserContext

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("RESEARCH RESULT")
                .scholiumApparatusHeadingStyle()
                .accessibilityAddTraits(.isHeader)
            if record.academicResults.isEmpty {
                Text("No academic result fields were configured for this Action.")
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(record.academicResults.enumerated()), id: \.element.id) {
                    index, result in
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Text(verbatim: result.definition.label)
                            .font(ScholiumTypography.interface(.sectionTitle))
                            .accessibilityAddTraits(.isHeader)
                        resultPresentation(result)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if index + 1 < record.academicResults.count {
                        ScholiumStructuralRule()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scholium.researchResult.finalized")
    }

    @ViewBuilder
    private func resultPresentation(
        _ result: PortableResearchAcademicFieldResult
    ) -> some View {
        switch result.value {
        case .freeText(let text):
            ResearchRecordProseView(
                source: text,
                sourceNote: context.proseNavigation.currentLocation(
                    for: record.researchRecordContextParticipant
                ),
                navigation: context.proseNavigation,
                openNote: context.openNote
            )
        case .singleChoice(let choice):
            plainValue(
                result.definition.choices.first { $0.value == choice }?.label ?? choice,
                isSupplied: true
            )
        case .multipleChoice(let choices):
            plainValue(
                choices.map { choice in
                    result.definition.choices.first { $0.value == choice }?.label ?? choice
                }.joined(separator: ", "),
                isSupplied: true
            )
        case nil:
            plainValue(String(localized: "Not supplied"), isSupplied: false)
        }
    }

    private func plainValue(_ value: String, isSupplied: Bool) -> some View {
        Text(verbatim: value)
            .font(ScholiumTypography.scholarly(.body))
            .scholiumForeground(isSupplied ? .primaryText : .secondaryText)
            .textSelection(.enabled)
    }
}
