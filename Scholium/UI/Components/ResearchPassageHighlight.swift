import NaturalLanguage
import SwiftUI

/// A shared, source-neutral highlight for research snippets in both Inspector panes.
enum ResearchPassageHighlight {
    static func matches(in text: String, ranges: [Range<Int>]) -> Text {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let common: Set<String> = ["如何", "用于", "可以", "进行", "以及", "或者", "the", "and", "for", "with", "that", "this"]
        var selected: [Range<String.Index>] = []
        var words: Set<String> = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let span = NSRange(range, in: text)
            let word = String(text[range]).lowercased()
            guard word.count >= 2, word.count <= 16, !common.contains(word), !words.contains(word),
                (span.location..<NSMaxRange(span)).allSatisfy({ index in ranges.contains { $0.contains(index) } })
            else { return true }
            selected.append(range)
            words.insert(word)
            return selected.count < 3
        }
        return styled(text, ranges: selected)
    }

    static func occurrences(in text: String, ranges: [Range<Int>]) -> Text {
        var merged: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound })
        where range.lowerBound >= 0 && !range.isEmpty && range.upperBound <= text.utf16.count {
            if let previous = merged.last, range.lowerBound <= previous.upperBound {
                merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return styled(text, ranges: merged.compactMap { Range(NSRange(location: $0.lowerBound, length: $0.count), in: text) })
    }

    private static func styled(_ text: String, ranges: [Range<String.Index>]) -> Text {
        var result = Text("")
        var cursor = text.startIndex
        for range in ranges {
            let before = Text(verbatim: String(text[cursor..<range.lowerBound]))
            let match = Text(verbatim: String(text[range]))
                .fontWeight(.medium)
                .customAttribute(ResearchMatchAttribute())
            result = Text("\(result)\(before)\(match)")
            cursor = range.upperBound
        }
        return Text("\(result)\(Text(verbatim: String(text[cursor...])))")
    }
}

private struct ResearchMatchAttribute: TextAttribute {}

/// Native redaction can rewrap mixed-script text. Keep the source's exact text
/// layout and render placeholder lines into it, without measuring/caching heights.
struct ResearchText: View {
    let text: Text
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        text
            .textRenderer(ResearchHighlightRenderer(isPlaceholder: redactionReasons.contains(.placeholder)))
            .environment(\.redactionReasons, redactionReasons.subtracting(.placeholder))
    }
}

/// Native Text owns layout and semantics; draw glyphs/highlights or placeholder lines.
struct ResearchHighlightRenderer: TextRenderer {
    var isPlaceholder = false

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            if isPlaceholder {
                let bounds = line.typographicBounds.rect
                let bar = bounds.insetBy(dx: 0, dy: bounds.height * 0.2)
                var placeholder = context
                placeholder.opacity *= 0.16
                placeholder.fill(
                    Path(roundedRect: bar, cornerRadius: ScholiumGrid.Spacing.opticalAlignmentAdjustment),
                    with: .foreground)
                continue
            }
            for run in line {
                if run[ResearchMatchAttribute.self] != nil {
                    let rect = run.typographicBounds.rect
                    context.fill(Path(rect), with: .color(.accentColor.opacity(0.12)))
                }
                context.draw(run)
            }
        }
    }
}
