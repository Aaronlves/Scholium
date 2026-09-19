import Foundation
import Testing

@testable import ScholiumApp

/// Review renders authored YAML by hand while Edit reads the same bytes through
/// a real YAML grammar. These cases pin the places the two used to disagree.
@Suite("Review YAML coloring")
@MainActor
struct ReviewFrontmatterMarkupTests {
    private func frontmatterHTML(_ yaml: String) -> String {
        SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<p>Body</p>",
            frontmatter: yaml
        )
    }

    @Test("A colon inside a plain scalar is not a key")
    func urlInSequenceMemberIsNotAKey() {
        let html = frontmatterHTML("source:\n  - https://example.com\n")
        // The authored key keeps its coloring.
        #expect(html.contains("<span class=\"cm-live-yaml-key\">source</span>:"))
        // The URL's scheme does not become a second one.
        #expect(!html.contains(">  - https</span>"))
        #expect(html.contains("cm-live-yaml-value\">  - https://example.com</span>"))
    }

    @Test("A colon without following space stays inside the scalar")
    func colonWithoutSpaceIsNotASeparator() {
        let html = frontmatterHTML("note: time is 10:30\nbare\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">note</span>:"))
        #expect(!html.contains("<span class=\"cm-live-yaml-key\">note: time is 10</span>"))
        // A line with no separator at all carries no key.
        #expect(!html.contains("<span class=\"cm-live-yaml-key\">bare"))
    }

    @Test("A colon inside a quoted scalar never separates")
    func quotedColonIsNotASeparator() {
        let html = frontmatterHTML("related:\n  - \"Kant: the first Critique\"\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">related</span>:"))
        #expect(!html.contains("cm-live-yaml-key\">  - &quot;Kant"))
        // Edit colors this member as a quoted string, so Review does too.
        #expect(html.contains("cm-live-yaml-string\">  - &quot;Kant"))
    }

    @Test("A quoted key is still a key")
    func quotedKeyIsRecognized() {
        let html = frontmatterHTML("\"my: key\": value\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">&quot;my: key&quot;</span>:"))
    }

    @Test("A mapping nested under a sequence indicator keeps its key")
    func mappingInsideSequenceItemKeepsItsKey() {
        let html = frontmatterHTML("sources:\n  - title: Critique\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">  - title</span>:"))
    }

    @Test("A key ending the line is a key")
    func trailingColonIsAKey() {
        let html = frontmatterHTML("keywords:\n  - kant\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">keywords</span>:"))
    }

    @Test("A plain scalar may begin with a dash")
    func negativeNumberIsNotASequenceIndicator() {
        let html = frontmatterHTML("offset: -5\ncomment_free\n")
        #expect(html.contains("<span class=\"cm-live-yaml-key\">offset</span>:"))
        #expect(!html.contains("<span class=\"cm-live-yaml-key\">comment_free"))
    }

    @Test("Comments keep their own coloring")
    func commentLineIsAComment() {
        let html = frontmatterHTML("# a note about: this\ntitle: Fixture\n")
        #expect(html.contains("cm-live-yaml-comment\"># a note about: this</span>"))
        #expect(html.contains("<span class=\"cm-live-yaml-key\">title</span>:"))
    }
}
