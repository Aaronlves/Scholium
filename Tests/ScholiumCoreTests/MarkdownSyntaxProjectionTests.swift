import Foundation
import Testing
@testable import ScholiumCore

@Suite("Live Preview syntax visibility")
struct MarkdownSyntaxProjectionTests {
    @Test("Caret inside a Markdown construct reveals its source markers")
    func caretInsideConstruct() {
        #expect(MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: NSRange(location: 10, length: 12),
            selections: [NSRange(location: 15, length: 0)],
            isEditable: true
        ))
    }

    @Test("Caret at either construct boundary reveals its source markers")
    func caretAtBoundaries() {
        let range = NSRange(location: 10, length: 12)
        #expect(MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: range,
            selections: [NSRange(location: 10, length: 0)],
            isEditable: true
        ))
        #expect(MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: range,
            selections: [NSRange(location: 22, length: 0)],
            isEditable: true
        ))
    }

    @Test("Distant or read-only selections keep syntax projected away")
    func hiddenOutsideEditableSelection() {
        let range = NSRange(location: 10, length: 12)
        #expect(!MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: range,
            selections: [NSRange(location: 30, length: 0)],
            isEditable: true
        ))
        #expect(!MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: range,
            selections: [NSRange(location: 15, length: 0)],
            isEditable: false
        ))
    }

    @Test("A selection crossing a construct reveals it")
    func intersectingSelection() {
        #expect(MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: NSRange(location: 10, length: 12),
            selections: [NSRange(location: 5, length: 8)],
            isEditable: true
        ))
    }

    @Test("Projection refresh keeps the anchored glyph at the same viewport position")
    func preservesViewportAnchor() {
        let origin = MarkdownSyntaxProjection.viewportOriginPreservingAnchor(
            currentOrigin: 240,
            anchorPositionBefore: 420,
            anchorPositionAfter: 452,
            maximumOrigin: 900
        )

        #expect(origin == 272)
    }

    @Test("Viewport restoration stays within document bounds")
    func clampsViewportRestoration() {
        #expect(MarkdownSyntaxProjection.viewportOriginPreservingAnchor(
            currentOrigin: 8,
            anchorPositionBefore: 80,
            anchorPositionAfter: 20,
            maximumOrigin: 900
        ) == 0)
        #expect(MarkdownSyntaxProjection.viewportOriginPreservingAnchor(
            currentOrigin: 880,
            anchorPositionBefore: 20,
            anchorPositionAfter: 80,
            maximumOrigin: 900
        ) == 900)
    }

    @Test("Editor deltas use UTF-16 offsets without corrupting emoji")
    func appliesUTF16Deltas() throws {
        let source = "A 🧭 claim"
        let compass = (source as NSString).range(of: "🧭")
        let updated = try MarkdownEditorDeltaApplier.apply([
            MarkdownEditorDelta(
                fromUTF16: NSMaxRange(compass),
                toUTF16: NSMaxRange(compass),
                insertion: " philosophical"
            ),
        ], to: source)
        #expect(updated == "A 🧭 philosophical claim")
    }

    @Test("Editor deltas reject overlapping or invalid ranges")
    func rejectsInvalidDeltas() {
        #expect(throws: MarkdownEditorDeltaError.self) {
            try MarkdownEditorDeltaApplier.apply([
                MarkdownEditorDelta(fromUTF16: 0, toUTF16: 3, insertion: "A"),
                MarkdownEditorDelta(fromUTF16: 2, toUTF16: 4, insertion: "B"),
            ], to: "abcdef")
        }
        #expect(throws: MarkdownEditorDeltaError.self) {
            try MarkdownEditorDeltaApplier.apply([
                MarkdownEditorDelta(fromUTF16: 0, toUTF16: 99, insertion: "A"),
            ], to: "short")
        }
    }
}
