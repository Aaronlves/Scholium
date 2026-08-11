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
        #expect(result.englishWords == 6)
        #expect(result.chineseCharacters == 2)
        #expect(result.characters == visible.count)
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
            englishWords: 1,
            chineseCharacters: 0,
            characters: 7,
            scope: .selection
        ))
    }

    @Test("Custom Wikilinks count their visible alias and comments remain absent")
    func customSyntax() {
        let result = DocumentStatisticsCalculator.calculate(
            markdownSource: "[[Target|Alias]] %%hidden%%"
        )
        #expect(result.englishWords == 1)
        #expect(result.chineseCharacters == 0)
        #expect(result.characters == 5)
    }

    @Test("Multiline comments and math delimiters do not enter visible counts")
    func commentsAndMath() {
        let result = DocumentStatisticsCalculator.calculate(
            markdownSource: "Visible %%hidden\nmore hidden%% $x$"
        )
        #expect(result.englishWords == 2)
        #expect(result.chineseCharacters == 0)
        #expect(result.characters == "Visible  x".count)
    }

    @Test("Characters use extended grapheme clusters without labeling other scripts English")
    func graphemeClusters() {
        let result = DocumentStatisticsCalculator.calculateVisibleText(
            "e\u{301} العربية",
            scope: .selection
        )
        #expect(result.englishWords == 1)
        #expect(result.chineseCharacters == 0)
        #expect(result.characters == 9)
    }
}
