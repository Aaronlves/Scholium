import Foundation
import ScholiumContracts
import Testing

@Suite("Citation carrier admission parity")
struct ZoteroMarkdownMarkerAdmissionTests {
    @Test(
        "Late reserved carriers retain complete-parser refusal, including Unicode case folding",
        arguments: [
            "scholium-zotero:1:AAAA", "ſcholium-zotero:1:AAAA", "[Readable](SCHOLIUM-ZOTERO:1:AAAA)",
            "[Readable](CiTe:field)", "<!--cite-bibliography:field-->", "<!--/cite-bibliography-->",
            "<!--scholium-zotero-field:1:AAAA-->", "<!--scholium-zotero-document:1:AAAA-->",
            "<!--/scholium-zotero-field-->",
        ])
    func lateMalformedCarrier(_ carrier: String) {
        let source = prefix + String(repeating: "Ordinary 中文 😀 e\u{301} prose.\r\n\r\n", count: 512) + carrier
        for snapshot: ZoteroCitationSnapshot? in [nil, absent] {
            let document = NoteDocument(relativePath: "Late.md", rawContent: source, citationSnapshot: snapshot)
            let catalog = ZoteroMarkdownFields(parsing: document)
            #expect(catalog == MarkdownSemanticDocument(parsing: document).zoteroFields)
            #expect(!catalog.canMutate && !catalog.diagnostics.isEmpty)
            #expect(catalog.fingerprint == document.fingerprint)
            #expect(catalog.fields.isEmpty && catalog.metadataSpans.isEmpty)
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }

    @Test(
        "Literal and escaped candidates keep their parser-owned exclusions",
        arguments: [
            "`[Readable](scholium-zotero:1:AAAA)`", "```markdown\r\n[Readable](cite:field)\r\n```",
            "    <!--cite-bibliography:field-->", "\\<!--scholium-zotero-field:1:AAAA-->",
            "<!-- example [Readable](cite:field) -->", "<span>[Readable](cite:field)</span>",
            "[About scholium-zotero:](https://example.invalid/)",
        ])
    func literalCandidates(_ body: String) {
        let source = prefix + body + "\r\n尾 😀 e\u{301} without final newline"
        for snapshot: ZoteroCitationSnapshot? in [nil, absent] {
            let document = NoteDocument(relativePath: "Literal.md", rawContent: source, citationSnapshot: snapshot)
            let catalog = ZoteroMarkdownFields(parsing: document)
            #expect(catalog == MarkdownSemanticDocument(parsing: document).zoteroFields)
            #expect(catalog.fields.isEmpty && catalog.documentState == nil)
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }

    @Test(
        "Combining and joined scheme endings retain the existing grapheme-boundary admission",
        arguments: ["\u{301}", "\u{307}", "\u{34F}", "\u{200D}", "\u{FE0F}"])
    func joinedSchemeEnding(_ suffix: String) {
        for scheme in ["scholium-zotero:", "cite:"] {
            let source = prefix + scheme + suffix + "field"
            for snapshot: ZoteroCitationSnapshot? in [nil, absent] {
                let document = NoteDocument(relativePath: "Joined.md", rawContent: source, citationSnapshot: snapshot)
                let catalog = ZoteroMarkdownFields(parsing: document)
                #expect(catalog.canMutate && !catalog.citationStateStale)
                #expect(catalog.fields.isEmpty && catalog.documentState == nil)
                #expect(catalog.fingerprint == document.fingerprint)
                #expect(document.sourceBytes == Data(source.utf8))
            }
        }
    }

    @Test("Long citation-free mixed source remains equivalent to complete semantic parsing")
    func citationFreeMixedSource() {
        let paragraph =
            "## Synthetic structure\r\n\r\n"
            + "A **bold** and *emphasized* claim links [[Target]] and cites [@synthetic2026, p. 12].\r\n\r\n"
            + "> [!note] A disposable callout\r\n> 中文 🦉 cafe\u{301} preserved.\r\n\r\n"
            + "- First point\r\n- Second point with footnote[^fixture]\r\n\r\n"
            + "| Claim | Source |\r\n| --- | --- |\r\n| Synthetic | [[Target]] |\r\n\r\n"
            + "[^fixture]: Synthetic footnote.\r\n\r\n"
        let source = prefix + String(repeating: paragraph, count: 512)
        for snapshot: ZoteroCitationSnapshot? in [nil, absent] {
            let document = NoteDocument(relativePath: "Long.md", rawContent: source, citationSnapshot: snapshot)
            let catalog = ZoteroMarkdownFields(parsing: document)
            #expect(catalog == MarkdownSemanticDocument(parsing: document).zoteroFields)
            #expect(catalog.canMutate && !catalog.citationStateStale)
            #expect(catalog.fields.isEmpty && catalog.documentState == nil)
            #expect(catalog.fingerprint == document.fingerprint)
            #expect(document.sourceBytes == Data(source.utf8))
        }
    }

    private let prefix = "\u{FEFF}---\r\nunknown: 'keep' # exact source\r\n---\r\n\r\n"
    private var absent: ZoteroCitationSnapshot { .init(noteID: UUID(), vaultID: UUID(), status: .absent) }
}
