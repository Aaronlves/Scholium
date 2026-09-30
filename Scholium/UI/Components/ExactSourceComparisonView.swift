import ScholiumContracts
import SwiftUI

struct ExactSourceComparisonSheetLayout<
    HeaderActions: View,
    Content: View,
    Footer: View
>: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource?
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
        .background(ScholiumNativeColorRole.windowBackground.color)
        .tint(ScholiumNativeColorRole.controlAccent.color)
        .accessibilityElement(children: .contain)
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
            if let detail {
                Text(detail)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    static func hasOnlySourceFormatChange(_ comparison: ExactSourceComparison) -> Bool {
        guard comparison.startingRevision != comparison.endingRevision else { return false }
        let removed = comparison.lines
            .filter { $0.kind == .startingOnly }
            .map { Array($0.text.utf8) }
        let inserted = comparison.lines
            .filter { $0.kind == .endingOnly }
            .map { Array($0.text.utf8) }
        return removed == inserted
    }

    static func differenceStartLineIDs(
        lines: [ExactSourceComparisonLine]
    ) -> [Int] {
        var starts: [Int] = []
        var previousWasChanged = false
        for line in displayOrderedLines(lines) {
            let changed = line.kind != .unchanged
            if changed && !previousWasChanged { starts.append(line.id) }
            previousWasChanged = changed
        }
        return starts
    }

    static func rows(
        lines: [ExactSourceComparisonLine]
    ) -> [ExactSourceComparisonPresentationRow] {
        guard lines.contains(where: { $0.kind != .unchanged }) else {
            return lines.isEmpty ? [] : [.folded(id: lines[0].id, lines: lines)]
        }
        var result: [ExactSourceComparisonPresentationRow] = []
        var index = 0
        let lines = displayOrderedLines(lines)
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
            let prefixCount =
                hasChangeBefore
                ? min(contextLineCount, run.count)
                : 0
            let suffixCount =
                hasChangeAfter
                ? min(contextLineCount, run.count - prefixCount)
                : 0
            let foldedCount = run.count - prefixCount - suffixCount

            if prefixCount > 0 {
                result.append(
                    contentsOf: run.prefix(prefixCount).map {
                        .line($0)
                    })
            }
            if foldedCount > 0 {
                let folded = Array(run.dropFirst(prefixCount).prefix(foldedCount))
                result.append(.folded(id: folded[0].id, lines: folded))
            }
            if suffixCount > 0 {
                result.append(
                    contentsOf: run.suffix(suffixCount).map {
                        .line($0)
                    })
            }
        }
        return result
    }

    /// CollectionDifference may report insertions before removals in one
    /// contiguous hunk. Present the prior source first, then the saved source.
    private static func displayOrderedLines(
        _ lines: [ExactSourceComparisonLine]
    ) -> [ExactSourceComparisonLine] {
        var ordered: [ExactSourceComparisonLine] = []
        var index = 0
        while index < lines.count {
            guard lines[index].kind != .unchanged else {
                ordered.append(lines[index])
                index += 1
                continue
            }
            let start = index
            while index < lines.count, lines[index].kind != .unchanged {
                index += 1
            }
            let hunk = lines[start..<index]
            ordered.append(contentsOf: hunk.filter { $0.kind == .startingOnly })
            ordered.append(contentsOf: hunk.filter { $0.kind == .endingOnly })
        }
        return ordered
    }
}

struct ExactSourceInlineSegment: Equatable {
    let text: String
    let changed: Bool
}

/// Presentation-only character comparison. `Character` boundaries keep a CJK
/// character or composed grapheme intact; the source comparison remains the
/// authority for exact lines, line endings, and revision identity.
enum ExactSourceInlinePresentation {
    static func segmentsByLineID(
        _ lines: [ExactSourceComparisonLine]
    ) -> [Int: [ExactSourceInlineSegment]] {
        var result: [Int: [ExactSourceInlineSegment]] = [:]
        var index = 0
        while index < lines.count {
            guard lines[index].kind != .unchanged else {
                index += 1
                continue
            }
            let start = index
            while index < lines.count, lines[index].kind != .unchanged {
                index += 1
            }
            let hunk = lines[start..<index]
            let removed = hunk.filter { $0.kind == .startingOnly }
            let inserted = hunk.filter { $0.kind == .endingOnly }
            for pairIndex in 0..<min(removed.count, inserted.count) {
                let (old, new) = pairedSegments(
                    removed[pairIndex].text,
                    inserted[pairIndex].text
                )
                result[removed[pairIndex].id] = old
                result[inserted[pairIndex].id] = new
            }
        }
        return result
    }

    static func pairedSegments(
        _ oldText: String,
        _ newText: String
    ) -> ([ExactSourceInlineSegment], [ExactSourceInlineSegment]) {
        let old = Array(oldText)
        let new = Array(newText)
        // Long source lines can contain pasted documents. Keep rendering bounded.
        guard old.count <= 2_048, new.count <= 2_048 else {
            return prefixSuffixSegments(old, new)
        }
        // Swift String/Character equality canonically normalizes. Compare each
        // complete grapheme's bytes so a normalization-only edit remains visible.
        let difference = new.map { Array(String($0).utf8) }
            .difference(from: old.map { Array(String($0).utf8) })
        let removed = Set(
            difference.compactMap { change -> Int? in
                guard case .remove(let offset, _, _) = change else { return nil }
                return offset
            })
        let inserted = Set(
            difference.compactMap { change -> Int? in
                guard case .insert(let offset, _, _) = change else { return nil }
                return offset
            })
        let oldMarks = expandedWordMarks(old, changed: removed)
        let newMarks = expandedWordMarks(new, changed: inserted)
        return (
            coalesced(old, changed: oldMarks.contains),
            coalesced(new, changed: newMarks.contains)
        )
    }

    private static func expandedWordMarks(
        _ characters: [Character],
        changed: Set<Int>
    ) -> Set<Int> {
        var result = changed
        var index = 0
        while index < characters.count {
            guard isLatinWordCharacter(characters[index]) else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count, isLatinWordCharacter(characters[index]) {
                index += 1
            }
            if (start..<index).contains(where: changed.contains) {
                result.formUnion(start..<index)
            }
        }
        return result
    }

    private static func isLatinWordCharacter(_ character: Character) -> Bool {
        let scalars = String(character).unicodeScalars
        guard scalars.count == 1, let value = scalars.first?.value else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
            || (48...57).contains(value)
    }

    private static func prefixSuffixSegments(
        _ old: [Character],
        _ new: [Character]
    ) -> ([ExactSourceInlineSegment], [ExactSourceInlineSegment]) {
        var prefix = 0
        while prefix < min(old.count, new.count),
            Array(String(old[prefix]).utf8) == Array(String(new[prefix]).utf8)
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
            Array(String(old[old.count - suffix - 1]).utf8)
                == Array(String(new[new.count - suffix - 1]).utf8)
        {
            suffix += 1
        }
        return (
            coalesced(old) { (prefix..<(old.count - suffix)).contains($0) },
            coalesced(new) { (prefix..<(new.count - suffix)).contains($0) }
        )
    }

    private static func coalesced(
        _ characters: [Character],
        changed: (Int) -> Bool
    ) -> [ExactSourceInlineSegment] {
        var result: [ExactSourceInlineSegment] = []
        for (index, character) in characters.enumerated() {
            let isChanged = changed(index)
            if let last = result.last, last.changed == isChanged {
                result[result.count - 1] = .init(
                    text: last.text + String(character), changed: isChanged
                )
            } else {
                result.append(.init(text: String(character), changed: isChanged))
            }
        }
        return result
    }
}

/// Pure unified-diff presentation shared by current editor conflicts and
/// Source comparison review. Input and consequential actions remain with their
/// respective owners.
struct ExactSourceComparisonView: View {
    @Environment(\.locale) private var locale
    let comparison: ExactSourceComparison
    let startingLabel: LocalizedStringResource
    let endingLabel: LocalizedStringResource
    let startingOnlyLabel: LocalizedStringResource
    let endingOnlyLabel: LocalizedStringResource
    let identifierPrefix: String

    @State private var expandedFoldIDs: Set<Int> = []

    var body: some View {
        let inlineSegments = ExactSourceInlinePresentation.segmentsByLineID(comparison.lines)
        VStack(alignment: .leading, spacing: 0) {
            revisionHeader
            ScholiumStructuralRule()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ExactSourceComparisonPresentation.rows(lines: comparison.lines)) {
                    row in
                    switch row {
                    case .line(let line):
                        diffLine(line, segments: inlineSegments[line.id])
                    case .folded(let id, let lines):
                        if expandedFoldIDs.contains(id) {
                            ForEach(lines) { line in diffLine(line, segments: nil) }
                        } else {
                            foldedLinesButton(id: id, count: lines.count)
                        }
                    }
                }
            }
            .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            .accessibilityElement(children: .contain)
        }
        .background(ScholiumNativeColorRole.textBackground.color)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
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
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(startingLabel)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text(endingLabel)
            }
            .font(ScholiumTypography.interface(.sectionTitle))

            if ExactSourceComparisonPresentation.hasOnlySourceFormatChange(comparison) {
                Text("Source format changed", bundle: .module)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
                    .help(Text("Line endings or the UTF-8 marker changed. Revision Details shows the exact formats.", bundle: .module))
            }

            DisclosureGroup {
                ViewThatFits(in: .horizontal) {
                    HStack(
                        alignment: .top,
                        spacing: ScholiumGrid.Spacing.sectionSeparation
                    ) {
                        revisionLabel(
                            title: startingLabel,
                            fingerprint: comparison.startingRevision,
                            hasBOM: comparison.startingHasUTF8BOM,
                            lineEndings: revisionLineEndings(starting: true)
                        )
                        revisionLabel(
                            title: endingLabel,
                            fingerprint: comparison.endingRevision,
                            hasBOM: comparison.endingHasUTF8BOM,
                            lineEndings: revisionLineEndings(starting: false)
                        )
                    }
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.nestedContentInset
                    ) {
                        revisionLabel(
                            title: startingLabel,
                            fingerprint: comparison.startingRevision,
                            hasBOM: comparison.startingHasUTF8BOM,
                            lineEndings: revisionLineEndings(starting: true)
                        )
                        revisionLabel(
                            title: endingLabel,
                            fingerprint: comparison.endingRevision,
                            hasBOM: comparison.endingHasUTF8BOM,
                            lineEndings: revisionLineEndings(starting: false)
                        )
                    }
                }
                .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
            } label: {
                Text("Revision Details", bundle: .module)
            }
            .scholiumActivationPointer()
            .font(ScholiumTypography.interface(.compact))
        }
        .padding(ScholiumGrid.Spacing.nestedContentInset)
    }

    private func revisionLabel(
        title: LocalizedStringResource,
        fingerprint: DocumentFingerprint,
        hasBOM: Bool,
        lineEndings: [ExactSourceComparisonLineEnding]
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(title)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text(short(fingerprint))
                .font(ScholiumTypography.exact(.small))
                .textSelection(.enabled)
            Text(
                hasBOM
                    ? LocalizedStringResource("UTF-8 BOM present", locale: locale, bundle: .module)
                    : LocalizedStringResource("No UTF-8 BOM", locale: locale, bundle: .module)
            )
            .font(ScholiumTypography.interface(.small))
            .scholiumForeground(.secondaryText)
            ForEach(lineEndings, id: \.self) { ending in
                Text(lineEndingLabel(ending))
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func diffLine(
        _ line: ExactSourceComparisonLine,
        segments: [ExactSourceInlineSegment]?
    ) -> some View {
        HStack(
            alignment: .top,
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
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                if line.text.isEmpty {
                    Text(verbatim: " ")
                        .font(ScholiumTypography.exact(.body))
                        .accessibilityLabel("Blank line")
                        .accessibilityHint(lineEndingLabel(line.lineEnding))
                } else {
                    decoratedText(for: line, segments: segments)
                        .font(ScholiumTypography.exact(.body))
                        .lineLimit(nil)
                        .textSelection(.enabled)
                        .accessibilityHint(lineEndingLabel(line.lineEnding))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(ScholiumTypography.exact(.small))
        .scholiumForeground(.secondaryText)
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumMetrics.DocumentWorkflow.conflictDiffRowVerticalInset)
        .background(backgroundColor(for: line.kind))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(accessibilityLabel(for: line.kind))
        .accessibilityValue(Text(verbatim: accessibilityValue(for: line)))
        .accessibilityHint(lineEndingLabel(line.lineEnding))
        .accessibilityIdentifier("\(identifierPrefix).row.\(line.id)")
        .id(line.id)
    }

    private func decoratedText(
        for line: ExactSourceComparisonLine,
        segments: [ExactSourceInlineSegment]?
    ) -> Text {
        guard line.kind != .unchanged else {
            return Text(verbatim: line.text)
                .foregroundColor(ScholiumColorRole.secondaryText.color)
        }
        let parts = segments ?? [.init(text: line.text, changed: true)]
        return parts.reduce(Text(verbatim: "")) { result, part in
            let text = Text(verbatim: part.text)
            let styled: Text
            if part.changed {
                switch line.kind {
                case .startingOnly:
                    styled =
                        text
                        .foregroundColor(ScholiumColorRole.comparisonRemoval.color)
                        .strikethrough()
                case .endingOnly:
                    styled =
                        text
                        .foregroundColor(ScholiumColorRole.comparisonInsertion.color)
                        .underline()
                case .unchanged:
                    styled = text
                }
            } else {
                styled = text.foregroundColor(ScholiumColorRole.primaryText.color)
            }
            return result + styled
        }
    }

    private func foldedLinesButton(id: Int, count: Int) -> some View {
        Button {
            expandedFoldIDs.insert(id)
        } label: {
            Label {
                Text("\(count) unchanged lines", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis")
            }
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
            .contentShape(Rectangle())
            .scholiumContentControlInk(
                resting: .secondaryText,
                emphasized: .accent
            )
        }
        .scholiumActivationPointer()
        .buttonStyle(.plain)
        .scholiumContentControlPointerFeedback(
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .scholiumForeground(.secondaryText)
        .accessibilityHint(Text("Shows the folded unchanged lines", bundle: .module))
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
        case .unchanged: .init("Unchanged", locale: locale, bundle: .module)
        case .startingOnly: startingOnlyLabel
        case .endingOnly: endingOnlyLabel
        }
    }

    private func accessibilityValue(
        for line: ExactSourceComparisonLine
    ) -> String {
        var starting = startingLabel
        starting.locale = locale
        var ending = endingLabel
        ending.locale = locale
        let positions = [
            line.startingLineNumber.map { "\(String(localized: starting)) \($0)" },
            line.endingLineNumber.map { "\(String(localized: ending)) \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
        let content =
            line.text.isEmpty
            ? ScholiumL10n.string("Blank line", locale: locale)
            : line.text
        return "\(positions) \(content)"
    }

    private func colorRole(
        for kind: ExactSourceComparisonLineKind
    ) -> ScholiumColorRole {
        switch kind {
        case .unchanged: .secondaryText
        case .startingOnly: .comparisonRemoval
        case .endingOnly: .comparisonInsertion
        }
    }

    private func backgroundColor(
        for kind: ExactSourceComparisonLineKind
    ) -> Color {
        switch kind {
        case .unchanged: .clear
        case .startingOnly: ScholiumColorRole.comparisonRemovalBackground.color
        case .endingOnly: ScholiumColorRole.comparisonInsertionBackground.color
        }
    }

    private func revisionLineEndings(
        starting: Bool
    ) -> [ExactSourceComparisonLineEnding] {
        let present = Set(
            comparison.lines.compactMap { line in
                let existsInRevision =
                    starting
                    ? line.startingLineNumber != nil
                    : line.endingLineNumber != nil
                return existsInRevision ? line.lineEnding : nil
            })
        return [.lf, .crlf, .none].filter(present.contains)
    }

    private func lineEndingLabel(
        _ ending: ExactSourceComparisonLineEnding
    ) -> LocalizedStringResource {
        switch ending {
        case .lf: .init("Line ending: LF", locale: locale, bundle: .module)
        case .crlf: .init("Line ending: CRLF", locale: locale, bundle: .module)
        case .none: .init("No line ending", locale: locale, bundle: .module)
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "SHA-256 \(fingerprint.sha256.prefix(12))… (\(fingerprint.byteCount) bytes)"
    }
}
