import Testing

@testable import ScholiumApp

@Suite("Document outline rail")
struct DocumentOutlineRailTests {
    @Test("Projection follows authored H1/H2 order and ignores frontmatter")
    func projectionUsesCurrentSourceHeadings() {
        let source = """
            ---
            title: "# Metadata, not a heading"
            ---
            # Introduction

            A paragraph.

            ## 第二节
            ### Detail
            """

        let entries = DocumentOutlineProjection.make(
            relativePath: "notes/example.md",
            source: source
        )

        #expect(entries.map(\.title) == ["Introduction", "第二节"])
        #expect(entries.map(\.level) == [1, 2])
        #expect(entries.map(\.sourceLine) == [4, 8])
        #expect(entries.map(\.sourceProgress) == entries.sorted { $0.sourceProgress < $1.sourceProgress }.map(\.sourceProgress))
    }

    @Test("Active marker follows a source anchor and falls back to scroll fraction")
    func activeMarkerSelection() {
        let entries = [
            DocumentOutlineEntry(
                id: "first",
                level: 1,
                title: "First",
                sourceLine: 1,
                sourceUTF16Offset: 0,
                sourceProgress: 0
            ),
            DocumentOutlineEntry(
                id: "second",
                level: 2,
                title: "Second",
                sourceLine: 12,
                sourceUTF16Offset: 40,
                sourceProgress: 0.5
            ),
            DocumentOutlineEntry(
                id: "third",
                level: 2,
                title: "Third",
                sourceLine: 24,
                sourceUTF16Offset: 80,
                sourceProgress: 1
            ),
        ]

        #expect(
            DocumentOutlineProjection.activeEntryID(
                entries: entries,
                sourceUTF16Offset: 55,
                scrollFraction: 0
            ) == "second"
        )
        #expect(
            DocumentOutlineProjection.activeEntryID(
                entries: entries,
                sourceUTF16Offset: nil,
                scrollFraction: 0.8
            ) == "second"
        )
        #expect(
            DocumentOutlineProjection.activeEntryID(
                entries: entries,
                sourceUTF16Offset: 0,
                scrollFraction: 1
            ) == "first"
        )
    }
}
