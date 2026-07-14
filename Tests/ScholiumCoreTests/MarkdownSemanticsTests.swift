import Foundation
import Testing
@testable import ScholiumCore

@Suite("Native Markdown semantic projections")
struct MarkdownSemanticsTests {
    @Test("Highlights preserve the exact UTF-16 source range")
    func highlightRanges() {
        let source = "前文 ==central claim== 后文"
        let highlight = MarkdownSemanticProjection.highlights(in: source).first
        #expect(highlight.map { (source as NSString).substring(with: $0.contentRange) } == "central claim")
        #expect(highlight.map { (source as NSString).substring(with: $0.range) } == "==central claim==")
    }

    @Test("Footnote references resolve multiline definitions but not definitions themselves")
    func footnotes() {
        let source = "Claim[^a].\n\n[^a]: First line\n  continued line\n"
        let references = MarkdownSemanticProjection.footnoteReferences(in: source)
        #expect(references.count == 1)
        #expect(references.first?.identifier == "a")
        #expect(references.first?.content == "First line continued line")
    }

    @Test("Callout blocks preserve fold markers without changing the source")
    func callouts() {
        let source = "> [!theorem]- Closure\n> Reasons transmit.\n\nOrdinary text."
        let callout = MarkdownSemanticProjection.callouts(in: source).first
        #expect(callout?.kind == "theorem")
        #expect(callout?.foldState == .collapsed)
        #expect(callout.map { (source as NSString).substring(with: $0.foldMarkerRange ?? NSRange()) } == "-")
        #expect(callout?.markerRanges.count == 2)
        #expect(callout.map { (source as NSString).substring(with: $0.blockRange) }?.contains("Reasons transmit") == true)
    }
}
