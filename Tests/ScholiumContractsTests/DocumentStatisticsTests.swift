import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Document statistics")
struct DocumentStatisticsTests {
    @Test("Statistics exclude YAML and Markdown syntax while retaining visible text")
    func visibleMarkdown() {
        let source = """
        ---
        title: Hidden Metadata
        ---
        # Hello-world 价值！

        A [visible](https://hidden.example) and ![diagram](image.png), `code`.
        """
        let result = DocumentStatisticsCalculator.calculate(markdownSource: source)
        let visible = "Hello-world 价值！\nA visible and diagram, code."
        #expect(result.words == 8)
        #expect(result.hanCharacters == 2)
        #expect(result.charactersWithSpaces == visible.count)
        #expect(result.charactersWithoutSpaces == 38)
        #expect(result.scope == .body)
    }

    @Test("A nonempty source selection becomes the only statistics scope")
    func selectedMarkdown() {
        let source = "Use [visible](https://hidden.example) here."
        let range = (source as NSString).range(of: "[visible](https://hidden.example)")
        let result = DocumentStatisticsCalculator.calculate(
            markdownSource: source,
            selectedUTF16Ranges: [range.location..<(range.location + range.length)]
        )
        #expect(result == DocumentStatistics(
            words: 1,
            charactersWithSpaces: 7,
            charactersWithoutSpaces: 7,
            hanCharacters: 0,
            scope: .selection
        ))
    }

    @Test("Custom Wikilinks count their visible alias and comments remain absent")
    func customSyntax() {
        let result = DocumentStatisticsCalculator.calculate(
            markdownSource: "[[Target|Alias]] %%hidden%%"
        )
        #expect(result.words == 1)
        #expect(result.hanCharacters == 0)
        #expect(result.charactersWithSpaces == 5)
        #expect(result.charactersWithoutSpaces == 5)
    }

    @Test("Multiline comments and math delimiters do not enter visible counts")
    func commentsAndMath() {
        let result = DocumentStatisticsCalculator.calculate(
            markdownSource: "Visible %%hidden\nmore hidden%% $x$"
        )
        #expect(result.words == 2)
        #expect(result.hanCharacters == 0)
        #expect(result.charactersWithSpaces == "Visible  x".count)
        #expect(result.charactersWithoutSpaces == "Visiblex".count)
    }

    @Test("Words are language-aware and characters use extended grapheme clusters")
    func graphemeClusters() {
        let result = DocumentStatisticsCalculator.calculateVisibleText(
            "e\u{301} العربية",
            scope: .selection
        )
        #expect(result.words == 2)
        #expect(result.hanCharacters == 0)
        #expect(result.charactersWithSpaces == 9)
        #expect(result.charactersWithoutSpaces == 8)
    }
}
