import Foundation

/// Read-only snippet formatting uses the existing dialect parser. Navigation
/// continues to use the original occurrence and its exact source span.
public enum ResearchExcerptPresentation {
    public static func readableText(_ source: String, includingAnnotations: Bool = false) -> String {
        let document = NoteDocument(relativePath: "snippet.md", rawContent: source)
        return readableText(
            document: document, semantic: MarkdownSemanticDocument(parsing: document),
            includingAnnotations: includingAnnotations)
    }

    /// Publication can share a snippet-local parse with its Search projection.
    /// Reparse mismatched material before using any source-relative link spans.
    package static func readableText(
        document: NoteDocument, semantic: MarkdownSemanticDocument, includingAnnotations: Bool = false
    ) -> String {
        let boundSemantic =
            semantic.fingerprint == document.fingerprint
            ? semantic : MarkdownSemanticDocument(parsing: document)
        let links = boundSemantic.links
        // Links presents annotations separately; related excerpts retain their wording.
        // Ignore nested occurrences inside an already consumed annotation.
        var visibleLinks: [LinkOccurrence] = []
        for link in links where link.syntax == .wikilink {
            if let previous = visibleLinks.last,
                link.span.utf16LowerBound < previous.span.utf16UpperBound
            {
                continue
            }
            visibleLinks.append(link)
        }
        let text = NSMutableString(string: document.rawContent)
        for link in visibleLinks.reversed() {
            let label =
                (link.alias ?? link.target)
                + (includingAnnotations ? link.annotation.map { " (" + $0.text + ")" } ?? "" : "")
            let escaped = label.map { character in
                "\\`*_{}[]()>#+-.!|".contains(character) ? "\\" + String(character) : String(character)
            }.joined()
            text.replaceCharacters(in: link.span.nsRange, with: "[" + escaped + "](scholium-snippet:)")
        }
        return MarkdownVisibleText.render(text as String)
    }
}
