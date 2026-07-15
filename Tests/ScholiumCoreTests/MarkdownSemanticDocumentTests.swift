import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Shared Markdown semantic document")
struct MarkdownSemanticDocumentTests {
    @Test("Retired relation arrows remain source-located neutral links")
    func v4RelationArrow() {
        let source = """
        ---
        schema_version: dissertation-control-v4
        ---
        # Claim

        ## Relations
        - `premise_of` -> [[Inference A]]
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "claim.md", rawContent: source))
        let relation = semantic.links.first { $0.syntax == .relationArrow }
        #expect(relation?.relationship == nil)
        #expect(relation?.vectorKind == .neutral)
        #expect(relation?.target == "Inference A")
        #expect(semantic.links.count == 1)
        #expect(semantic.diagnostics.contains { $0.code == .noncanonicalRelationshipSyntax })
    }

    @Test("Relation-looking prose outside the canonical section stays a neutral link")
    func relationArrowSectionBoundary() {
        let source = "---\nschema_version: dissertation-control-v4\n---\n# Note\n\n- `supports` -> [[Target]]\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "note.md", rawContent: source))
        #expect(semantic.links.count == 1)
        #expect(semantic.links[0].syntax == .wikilink)
        #expect(semantic.links[0].relationship == nil)
    }

    @Test("Legacy arrows stay neutral and diagnostic without a v4 schema")
    func relationArrowSchemaBoundary() {
        let source = "# Legacy\n\n## Relations\n- `supports` -> [[Target]]\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "legacy.md", rawContent: source))
        #expect(semantic.links.count == 1)
        #expect(semantic.links[0].syntax == .relationArrow)
        #expect(semantic.links[0].relationship == nil)
        #expect(semantic.links[0].vectorKind == .neutral)
        #expect(semantic.diagnostics.contains { $0.code == .noncanonicalRelationshipSyntax })
    }

    @Test("Legacy predicate aliases stay readable but semantically neutral")
    func v4LegacyAliasBoundary() {
        let source = "---\nschema_version: dissertation-control-v4\n---\n# Claim\n\n## Relations\n- [[Target|:supports]]\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "claim.md", rawContent: source))
        #expect(semantic.links.first?.relationship == nil)
        #expect(semantic.links.first?.vectorKind == .neutral)
        #expect(semantic.diagnostics.contains { $0.code == .noncanonicalRelationshipSyntax })
    }

    @Test("Unknown canonical relation predicates remain visible diagnostics")
    func unknownRelationPredicate() {
        let source = "---\nschema_version: dissertation-control-v4\n---\n# Note\n\n## Relations\n- `probably_supports` -> [[Target]]\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "note.md", rawContent: source))
        #expect(semantic.diagnostics.contains { $0.code == .unknownRelationshipPredicate })
        #expect(semantic.links.first?.relationship == nil)
    }

    @Test("Retired reified relations remain ordinary neutral links")
    func reifiedRelation() {
        let source = """
        ---
        schema_version: dissertation-control-v4
        ---
        # Pressure Record

        ## Relation
        - Subject: [[Objection A]]
        - Predicate: `pressures`
        - Object: [[Claim B]]

        ## Relations
        - `depends_on` -> [[Evidence Check]]
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "relation.md", rawContent: source))
        #expect(semantic.links.contains { $0.target == "Objection A" && $0.vectorKind == .neutral })
        #expect(semantic.links.contains { $0.target == "Claim B" && $0.vectorKind == .neutral })
    }

    @Test("Vector links parse everywhere ordinary wikilinks are valid")
    func vectorLinks() {
        let source = """
        ---
        title: Vector Fixture
        hidden: "+[[YAML Literal]]"
        ---
        A +[[Supported]] and -[[Supporting]] while ?[[Incompatible]] and [[Related]].
        + [[List Neutral]]
        \\+[[Escaped Marker]]
        C++[[Adjacent Word]]
        ![[Embedded]]
        `+[[Inline Code]]`
        ``?[[Long Inline Code]]``
        ```md
        -[[Fenced Code]]
        ```
        %% -[[Commented]] %%
        <!-- ?[[HTML Commented]] -->
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "Vector.md", rawContent: source))
        let byTarget = Dictionary(uniqueKeysWithValues: semantic.links.map { ($0.target, $0) })

        #expect(byTarget["Supported"]?.vectorKind == .supportsTarget)
        #expect(byTarget["Supporting"]?.vectorKind == .supportedByTarget)
        #expect(byTarget["Incompatible"]?.vectorKind == .incompatible)
        #expect(byTarget["Related"]?.vectorKind == .neutral)
        #expect(byTarget["List Neutral"]?.vectorKind == .neutral)
        #expect(byTarget["Escaped Marker"]?.vectorKind == .neutral)
        #expect(byTarget["Adjacent Word"]?.vectorKind == .neutral)
        #expect(byTarget["Embedded"]?.syntax == .embed)
        #expect(byTarget["Embedded"]?.vectorKind == nil)
        #expect(byTarget["Inline Code"] == nil)
        #expect(byTarget["Long Inline Code"] == nil)
        #expect(byTarget["Fenced Code"] == nil)
        #expect(byTarget["Commented"] == nil)
        #expect(byTarget["HTML Commented"] == nil)
        #expect(byTarget["YAML Literal"] == nil)
        #expect((source as NSString).substring(with: byTarget["Supported"]!.span.nsRange) == "+[[Supported]]")
    }

    @Test("Mismatched backtick runs do not suppress valid vector links")
    func mismatchedBackticks() {
        let source = "` unmatched +[[Visible]] ``\nText ``` ?[[Hidden]] ```"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "ticks.md", rawContent: source))
        #expect(semantic.links.contains { $0.target == "Visible" && $0.vectorKind == .supportsTarget })
        #expect(!semantic.links.contains { $0.target == "Hidden" })
    }
    @Test("Source spans remain exact across BOM, CRLF, and Unicode")
    func sourceSpans() throws {
        let source = "\u{FEFF}---\r\ntitle: 范围\r\n---\r\n\r\n# 哲学 🧭\r\n\r\nBody."
        let document = NoteDocument(relativePath: "unicode.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let heading = try #require(semantic.headings.first)

        #expect(heading.text == "哲学 🧭")
        #expect(heading.span.start.line == 5)
        #expect((source as NSString).substring(with: heading.span.nsRange) == "# 哲学 🧭")
        #expect(Data(source.utf8)[heading.span.utf8Range] == Data("# 哲学 🧭".utf8))
    }

    @Test("Obsidian callouts are typed without parsing literal regions")
    func callouts() {
        let source = """
        ```md
        > [!flag] Not a callout
        ```

        > [!orient] Scope
        > This note maps the issue.

        > [!cite]- Sources
        > Checked source.

        > [!connect] Neighboring notes
        > [[Related Note]]

        > [!state] Normative reason
        > A reason that counts in favour.

        > [!illustrate] Evil Demon
        > A concrete test case.

        > [!quote] Author (2026, p. 1)
        > “Exact wording.”

        > [!flag]+ Source-status limit
        > Verification remains incomplete.

        > [!mini] Legacy orientation
        > Preserved legacy source.

        > [!bibli:] Legacy sources
        > Preserved legacy source.

        > [!project:] Legacy connections
        > Preserved legacy source.

        > [!theorem] Legacy statement
        > Preserved legacy source.

        > [!dialogue] Legacy illustration
        > Preserved legacy source.

        > [!author] Legacy quotation
        > Preserved legacy source.

        > [!torn] Legacy caution
        > Preserved legacy source.

        > [!bespoke] Preserved
        > Unknown kinds remain readable.
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "callouts.md", rawContent: source))

        #expect(semantic.callouts.count == 15)
        #expect(Array(semantic.callouts.prefix(7).map(\.kind)) == [
            "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
        ])
        #expect(Array(semantic.callouts.prefix(7).map(\.role)) == [
            .orient, .cite, .connect, .state, .illustrate, .quote, .flag,
        ])
        #expect(Array(semantic.callouts.dropFirst(7).prefix(7).map(\.kind)) == [
            "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
        ])
        #expect(semantic.callouts[7].rawKind == "mini")
        #expect(semantic.callouts[1].foldState == .collapsed)
        #expect(semantic.callouts[6].foldState == .expanded)
        #expect(semantic.callouts[3].bodySource == "A reason that counts in favour.")
        #expect(semantic.callouts[14].kind == "bespoke")
        #expect(semantic.callouts[14].role == .neutral)
        #expect(semantic.diagnostics.contains { $0.code == .unknownCallout })
    }

    @Test("Named, repeated, inline, missing, and unused footnotes stay distinct")
    func footnotes() {
        let source = """
        First[^reason], repeated[^reason], missing[^missing], inline^[Inline *content*].

        [^reason]: First line
          second line
        [^unused]: Not cited.
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "footnotes.md", rawContent: source))
        let named = semantic.footnoteReferences.filter { $0.identifier == "reason" }
        let inline = semantic.footnoteReferences.first { $0.isInline }

        #expect(named.map(\.occurrence) == [1, 2])
        #expect(named.allSatisfy { $0.ordinal == 1 })
        #expect(inline?.ordinal == 3)
        #expect(semantic.footnoteDefinitions.first { $0.identifier == "reason" }?.content == "First line\nsecond line")
        #expect(semantic.diagnostics.contains { $0.code == .undefinedFootnote })
        #expect(semantic.diagnostics.contains { $0.code == .unreferencedFootnote })
    }

    @Test("Links share one syntax-aware source-location contract")
    func links() {
        let source = """
        前置 🧭 [[Paper#Claim|:supports]] and [Topic](topics/Topic%20Name.md#Scope).
        `[[Ignored]]`
        %% [[Commented]] %%
        ![[figure.png|320]]
        """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "links.md", rawContent: source))

        #expect(semantic.links.count == 3)
        let relation = semantic.links[0]
        #expect(relation.target == "Paper")
        #expect(relation.fragment == "Claim")
        #expect(relation.relationship == nil)
        #expect(relation.vectorKind == .neutral)
        #expect(relation.span.start.line == 1)
        #expect((source as NSString).substring(with: relation.span.nsRange) == "[[Paper#Claim|:supports]]")
        #expect(semantic.diagnostics.contains { $0.code == .noncanonicalRelationshipSyntax })

        #expect(semantic.links[1].target == "topics/Topic Name.md")
        #expect(semantic.links[1].fragment == "Scope")
        #expect(semantic.links[2].syntax == .embed)
        #expect(semantic.links[2].target == "figure.png")
    }

    @Test("Duplicate footnote definitions are visible diagnostics")
    func duplicateFootnotes() {
        let source = "Claim[^x].\n\n[^x]: First.\n[^x]: Second.\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "duplicate.md", rawContent: source))
        #expect(semantic.footnoteDefinitions.count == 1)
        #expect(semantic.diagnostics.contains { $0.code == .duplicateFootnote })
    }
}
