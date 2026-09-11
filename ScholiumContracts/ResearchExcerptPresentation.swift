import Foundation

/// Read-only snippet formatting uses the existing dialect parser. Navigation
/// continues to use the original occurrence and its exact source span.
public enum ResearchExcerptPresentation {
    public static func readableText(_ source: String) -> String {
        let document = NoteDocument(relativePath: "snippet.md", rawContent: source)
        let links = MarkdownSemanticDocument(parsing: document).links
        // Annotation content is presented separately. Ignore nested occurrences
        // inside an already consumed annotation before replacing source ranges.
        var visibleLinks: [LinkOccurrence] = []
        for link in links where link.syntax == .wikilink {
            if let previous = visibleLinks.last,
                link.span.utf16LowerBound < previous.span.utf16UpperBound
            {
                continue
            }
            visibleLinks.append(link)
        }
        let text = NSMutableString(string: source)
        for link in visibleLinks.reversed() {
            let label = link.alias ?? link.target
            let escaped = label.map { character in
                "\\`*_{}[]()>#+-.!|".contains(character) ? "\\" + String(character) : String(character)
            }.joined()
            text.replaceCharacters(in: link.span.nsRange, with: "[" + escaped + "](scholium-snippet:)")
        }
        return MarkdownVisibleText.render(text as String)
    }
}
