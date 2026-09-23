import Foundation
import Testing

@testable import ScholiumApp

@Suite("Native editor state boundaries")
struct NativeEditorContractsTests {
    @Test("Restored selection ranges reject empty collections and out-of-document endpoints")
    func selectionBounds() {
        #expect(
            markdownEditorSelectionRangesAreValid([.init(anchor: 3, head: 0)], forEditorUTF16Length: 3))
        #expect(
            markdownEditorSelectionRangesAreValid([.init(anchor: 0, head: 0)], forEditorUTF16Length: 0))
        #expect(!markdownEditorSelectionRangesAreValid([], forEditorUTF16Length: 3))
        #expect(
            !markdownEditorSelectionRangesAreValid([.init(anchor: -1, head: 0)], forEditorUTF16Length: 3))
        #expect(
            !markdownEditorSelectionRangesAreValid(
                [.init(anchor: 0, head: Int.max)], forEditorUTF16Length: 3))
        #expect(
            !markdownEditorSelectionRangesAreValid([.init(anchor: 0, head: 0)], forEditorUTF16Length: -1))
    }

    @Test("Native selection boundaries reject surrogate interiors but allow combining scalars")
    func scalarBoundaries() {
        let text = "A😀e\u{301}"
        #expect(markdownEditorSelectionRangesAreValid([.init(anchor: 1, head: 3)], forProjectedText: text))
        #expect(markdownEditorSelectionRangesAreValid([.init(anchor: 4, head: 5)], forProjectedText: text))
        #expect(!markdownEditorSelectionRangesAreValid([.init(anchor: 2, head: 2)], forProjectedText: text))
        #expect(!markdownEditorSelectionRangesAreValid([.init(anchor: 0, head: 2)], forProjectedText: text))
        #expect(!markdownEditorSelectionRangesAreValid([.init(anchor: 0, head: 99)], forProjectedText: text))
    }

    @Test("Selection mapping retains passage edges and caret affinity across insertion and replacement")
    func selectionMapping() {
        let passage = NSRange(location: 5, length: 4)
        #expect(
            NativeDocumentSelectionMapping.map(passage, replacing: .init(location: 1, length: 0), replacementUTF16Length: 3) == .init(location: 8, length: 4))
        #expect(
            NativeDocumentSelectionMapping.map(passage, replacing: .init(location: 5, length: 0), replacementUTF16Length: 3) == .init(location: 8, length: 4))
        #expect(NativeDocumentSelectionMapping.map(passage, replacing: .init(location: 9, length: 0), replacementUTF16Length: 3) == passage)
        #expect(
            NativeDocumentSelectionMapping.map(passage, replacing: .init(location: 6, length: 2), replacementUTF16Length: 1) == .init(location: 5, length: 3))
        #expect(
            NativeDocumentSelectionMapping.map(.init(location: 5, length: 0), replacing: .init(location: 5, length: 0), replacementUTF16Length: 2)
                == .init(location: 7, length: 0))
    }

    @Test("Scroll restoration rejects unbound source positions and non-finite geometry")
    func scrollAnchors() {
        func anchor(
            offset: Int = 3, blockEnd: Int = 4, fraction: Double = 0.5, fingerprint: String = "revision"
        ) -> EditorScrollAnchor {
            .init(
                sourceFingerprint: fingerprint, sourceUTF16Offset: offset, blockUTF16LowerBound: 2,
                blockUTF16UpperBound: blockEnd, relativeBlockPosition: fraction, fallbackFraction: 0.5)
        }
        #expect(anchor().isValid(forUTF16Length: 4))
        #expect(!anchor(offset: 1).isValid(forUTF16Length: 4))
        #expect(!anchor(blockEnd: 5).isValid(forUTF16Length: 4))
        #expect(!anchor(fraction: .nan).isValid(forUTF16Length: 4))
        #expect(!anchor(fraction: .infinity).isValid(forUTF16Length: 4))
        #expect(!anchor(fingerprint: "").isValid(forUTF16Length: 4))
    }

    @Test("Availability changes for a selected passage but not ordinary caret motion")
    func availabilityProjection() {
        func context(_ range: MarkdownEditorSelectionRange) -> MarkdownEditorContext {
            .init(
                selections: [range], activeInlineConstructs: [], activeBlockConstructs: [],
                tablePosition: nil,
                composing: false, availableCommands: [.bold], undoLabel: nil, redoLabel: nil)
        }
        let first = EditorInteractionAvailability(context: context(.init(anchor: 1, head: 1)))
        let moved = EditorInteractionAvailability(context: context(.init(anchor: 5, head: 5)))
        let passage = EditorInteractionAvailability(context: context(.init(anchor: 1, head: 5)))
        #expect(first == moved)
        #expect(first != passage)
        #expect(
            passage.context(selections: [.init(anchor: 2, head: 6)]).selections == [
                .init(anchor: 2, head: 6)
            ])
    }
}
