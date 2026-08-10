import ScholiumContracts
import SwiftUI

struct ExactSourceComparisonSheetLayout<
    HeaderActions: View,
    Content: View,
    Footer: View
>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let identifier: String
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    headerCopy
                    Spacer(minLength: 0)
                    headerActions()
                }

                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    headerCopy
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        headerActions()
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScholiumStructuralRule()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScholiumStructuralRule()
            footer()
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.Comparison.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.Comparison.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.Comparison.minimumHeight,
            idealHeight: ScholiumMetrics.ResearchSheet.Comparison.idealHeight
        )
        .scholiumSurface(.boundedPanel)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(identifier)
    }

    private var headerCopy: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing
        ) {
            Text(title)
                .font(ScholiumTypography.interface(.primaryTitle))
                .accessibilityHeading(.h1)
            Text(detail)
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum ExactSourceComparisonPresentationRow: Hashable, Identifiable {
    case line(ExactSourceComparisonLine)
    case folded(id: Int, lines: [ExactSourceComparisonLine])

    var id: String {
        switch self {
        case .line(let line): "line-\(line.id)"
        case .folded(let id, _): "fold-\(id)"
        }
    }
}

enum ExactSourceComparisonPresentation {
    static let contextLineCount = 3

    static func rows(
        lines: [ExactSourceComparisonLine]
    ) -> [ExactSourceComparisonPresentationRow] {
        guard lines.contains(where: { $0.kind != .unchanged }) else {
            return lines.isEmpty ? [] : [.folded(id: lines[0].id, lines: lines)]
        }
        var result: [ExactSourceComparisonPresentationRow] = []
        var index = 0
        while index < lines.count {
            guard lines[index].kind == .unchanged else {
                result.append(.line(lines[index]))
                index += 1
                continue
            }
            let runStart = index
            while index < lines.count, lines[index].kind == .unchanged {
                index += 1
            }
            let run = Array(lines[runStart..<index])
            let hasChangeBefore = runStart > 0
            let hasChangeAfter = index < lines.count
            let prefixCount = hasChangeBefore
                ? min(contextLineCount, run.count)
                : 0
            let suffixCount = hasChangeAfter
                ? min(contextLineCount, run.count - prefixCount)
                : 0
            let foldedCount = run.count - prefixCount - suffixCount

            if prefixCount > 0 {
                result.append(contentsOf: run.prefix(prefixCount).map {
                    .line($0)
                })
            }
            if foldedCount > 0 {
                let folded = Array(run.dropFirst(prefixCount).prefix(foldedCount))
                result.append(.folded(id: folded[0].id, lines: folded))
            }
            if suffixCount > 0 {
                result.append(contentsOf: run.suffix(suffixCount).map {
                    .line($0)
                })
            }
        }
        return result
    }
}

/// Pure unified-diff presentation shared by current editor conflicts and
/// Research Record review. Input and consequential actions remain with their
/// respective owners.
struct ExactSourceComparisonView: View {
    let comparison: ExactSourceComparison
    let startingLabel: LocalizedStringResource
    let endingLabel: LocalizedStringResource
    let startingOnlyLabel: LocalizedStringResource
    let endingOnlyLabel: LocalizedStringResource
    let identifierPrefix: String

    @State private var expandedFoldIDs: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            revisionHeader
            ScholiumStructuralRule()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ExactSourceComparisonPresentation.rows(lines: comparison.lines)) {
                    row in
                    switch row {
                    case .line(let line):
                        diffLine(line)
                    case .folded(let id, let lines):
                        if expandedFoldIDs.contains(id) {
                            ForEach(lines) { line in diffLine(line) }
                        } else {
                            foldedLinesButton(id: id, count: lines.count)
                        }
                    }
                }
            }
            .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        }
        .background(ScholiumColorRole.documentBackground.color)
        .clipShape(RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
            .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).diff")
    }

    private var revisionHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                revisionLabel(
                    title: startingLabel,
                    fingerprint: comparison.startingRevision,
                    hasBOM: comparison.startingHasUTF8BOM
                )
                revisionLabel(
                    title: endingLabel,
                    fingerprint: comparison.endingRevision,
                    hasBOM: comparison.endingHasUTF8BOM
                )
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                revisionLabel(
                    title: startingLabel,
                    fingerprint: comparison.startingRevision,
                    hasBOM: comparison.startingHasUTF8BOM
                )
                revisionLabel(
                    title: endingLabel,
                    fingerprint: comparison.endingRevision,
                    hasBOM: comparison.endingHasUTF8BOM
                )
            }
        }
        .padding(ScholiumGrid.Spacing.nestedContentInset)
    }

    private func revisionLabel(
        title: LocalizedStringResource,
        fingerprint: DocumentFingerprint,
        hasBOM: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(title)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text(short(fingerprint))
                .font(ScholiumTypography.exact(.small))
                .textSelection(.enabled)
            Text(hasBOM ? "UTF-8 BOM present" : "No UTF-8 BOM")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func diffLine(_ line: ExactSourceComparisonLine) -> some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumMetrics.DocumentWorkflow.exactDiffColumnSpacing
        ) {
            Text(line.startingLineNumber.map(String.init) ?? "")
                .frame(
                    width: ScholiumMetrics.DocumentWorkflow.exactDiffLineNumberWidth,
                    alignment: .trailing
                )
            Text(line.endingLineNumber.map(String.init) ?? "")
                .frame(
                    width: ScholiumMetrics.DocumentWorkflow.exactDiffLineNumberWidth,
                    alignment: .trailing
                )
            Text(marker(for: line.kind))
                .font(ScholiumTypography.exact(.strong))
                .scholiumForeground(colorRole(for: line.kind))
                .frame(width: ScholiumMetrics.DocumentWorkflow.exactDiffMarkerWidth)
                .accessibilityLabel(accessibilityLabel(for: line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .font(ScholiumTypography.exact(.body))
        .scholiumForeground(
            line.kind == .unchanged ? .secondaryText : .primaryText
        )
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumMetrics.DocumentWorkflow.conflictDiffRowVerticalInset)
        .background(
            line.kind == .unchanged
                ? Color.clear
                : ScholiumColorRole.raisedSurfaceBackground.color
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).row.\(line.id)")
    }

    private func foldedLinesButton(id: Int, count: Int) -> some View {
        Button {
            expandedFoldIDs.insert(id)
        } label: {
            Label(
                "\(count) unchanged lines",
                systemImage: "ellipsis"
            )
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scholiumForeground(.secondaryText)
        .accessibilityHint("Shows the folded unchanged lines")
        .accessibilityIdentifier("\(identifierPrefix).unchanged.\(id)")
    }

    private func marker(for kind: ExactSourceComparisonLineKind) -> String {
        switch kind {
        case .unchanged: " "
        case .startingOnly: "−"
        case .endingOnly: "+"
        }
    }

    private func accessibilityLabel(
        for kind: ExactSourceComparisonLineKind
    ) -> LocalizedStringResource {
        switch kind {
        case .unchanged: "Unchanged"
        case .startingOnly: startingOnlyLabel
        case .endingOnly: endingOnlyLabel
        }
    }

    private func colorRole(
        for kind: ExactSourceComparisonLineKind
    ) -> ScholiumColorRole {
        switch kind {
        case .unchanged: .secondaryText
        case .startingOnly, .endingOnly: .attention
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "SHA-256 \(fingerprint.sha256.prefix(12))… (\(fingerprint.byteCount) bytes)"
    }
}
