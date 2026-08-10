import AppKit
import ScholiumContracts
import SwiftUI

struct ResearchFinalizedResultView: View {
    let record: PortableResearchRecord

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
                        Text(verbatim: resultValue(result))
                            .font(ScholiumTypography.scholarly(.body))
                            .scholiumForeground(
                                result.value == nil
                                    ? .secondaryText
                                    : .primaryText
                            )
                            .textSelection(.enabled)
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

    private func resultValue(_ result: PortableResearchAcademicFieldResult) -> String {
        guard let value = result.value else { return String(localized: "Not supplied") }
        return switch value {
        case .freeText(let text):
            text
        case .singleChoice(let choice):
            result.definition.choices.first { $0.value == choice }?.label ?? choice
        case .multipleChoice(let choices):
            choices.map { choice in
                result.definition.choices.first { $0.value == choice }?.label ?? choice
            }.joined(separator: ", ")
        }
    }
}
