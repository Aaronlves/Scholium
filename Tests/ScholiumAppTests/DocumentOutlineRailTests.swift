import CoreGraphics
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Document outline rail")
struct DocumentOutlineRailTests {
    @Test("Hydrated heading reuse preserves exact spans and dirty source is parsed independently")
    func hydratedHeadingsRequireExactSource() {
        let source = "\u{FEFF}---\r\ntitle: Metadata\r\n---\r\n# é 😀\r\n### Hidden detail\r\n## Following\r\n"
        let document = NoteDocument(relativePath: "Outline.md", rawContent: source)
        let snapshot = WorkspaceNoteSnapshot(
            id: .init(vaultID: UUID(), relativePath: document.relativePath),
            stableIdentity: .resolved(UUID()), document: document,
            fileMetadata: .init(byteCount: source.utf8.count, creationDate: nil, modificationDate: nil),
            graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)
        )
        let committed = DocumentOutlineProjection.make(snapshot: snapshot, source: source)
        #expect(committed == DocumentOutlineProjection.make(relativePath: document.relativePath, source: source))
        #expect(committed.map(\.title) == ["é 😀", "Following"])
        #expect(committed.last?.id.hasSuffix("-2") == true)

        let edited = source.replacingOccurrences(of: "é", with: "e\u{301}")
        #expect(source == edited)
        #expect(!source.utf8.elementsEqual(edited.utf8))
        let dirty = DocumentOutlineProjection.make(snapshot: snapshot, source: edited)
        #expect(dirty == DocumentOutlineProjection.make(relativePath: document.relativePath, source: edited))
        #expect(dirty.last?.sourceUTF16Offset == committed.last!.sourceUTF16Offset + 1)
        #expect(DocumentOutlineProjection.make(snapshot: snapshot, source: "# New heading\n").map(\.title) == ["New heading"])
        #expect(DocumentOutlineProjection.make(snapshot: snapshot, source: "").isEmpty)
    }

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

    @Test("Overflow fades appear only where the rail has hidden markers")
    func overflowEdges() {
        let fitting = DocumentOutlineScrollEdges(
            visibleRect: CGRect(x: 0, y: 0, width: 32, height: 200),
            contentHeight: 200
        )
        #expect(!fitting.hasAbove && !fitting.hasBelow)

        let top = DocumentOutlineScrollEdges(
            visibleRect: CGRect(x: 0, y: 0, width: 32, height: 200),
            contentHeight: 400
        )
        #expect(!top.hasAbove && top.hasBelow)

        let middle = DocumentOutlineScrollEdges(
            visibleRect: CGRect(x: 0, y: 100, width: 32, height: 200),
            contentHeight: 400
        )
        #expect(middle.hasAbove && middle.hasBelow)

        let bottom = DocumentOutlineScrollEdges(
            visibleRect: CGRect(x: 0, y: 200, width: 32, height: 200),
            contentHeight: 400
        )
        #expect(bottom.hasAbove && !bottom.hasBelow)
    }

    @Test("Preview placement meets the marker's inward edge in either layout direction")
    func previewPlacement() {
        let marker = CGRect(x: 0, y: 2, width: 32, height: 12)
        let previewSize = CGSize(width: 72, height: 40)
        let gap: CGFloat = 4
        let leftToRight = DocumentOutlinePreviewPlacement.origin(
            markerBounds: marker,
            railHeight: 200,
            documentViewportHeight: 600,
            previewSize: previewSize,
            gap: gap,
            layoutDirection: .leftToRight
        )
        #expect(leftToRight.x + previewSize.width == marker.minX - gap)
        #expect(leftToRight.y + previewSize.height / 2 == marker.midY)

        let rightToLeft = DocumentOutlinePreviewPlacement.origin(
            markerBounds: marker,
            railHeight: 200,
            documentViewportHeight: 600,
            previewSize: previewSize,
            gap: gap,
            layoutDirection: .rightToLeft
        )
        #expect(rightToLeft.x == marker.maxX + gap)
        #expect(rightToLeft.y + previewSize.height / 2 == marker.midY)

        let lastMarker = CGRect(x: 0, y: 190, width: 32, height: 12)
        let nearBottom = DocumentOutlinePreviewPlacement.origin(
            markerBounds: lastMarker,
            railHeight: 200,
            documentViewportHeight: 200,
            previewSize: previewSize,
            gap: gap,
            layoutDirection: .leftToRight
        )
        #expect(nearBottom.y + previewSize.height == 200)
    }
}
