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

    static func link(in text: String, label: String) -> Text {
        // Do not guess which occurrence is the authored link if its label repeats.
        guard !label.isEmpty, let range = text.range(of: label),
            text.range(of: label, range: range.upperBound..<text.endIndex) == nil
        else { return Text(verbatim: text) }
        return styled(text, ranges: [range])
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

/// Draw only the highlight background; native Text keeps glyph layout and semantics.
struct ResearchHighlightRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
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
