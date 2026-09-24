import AppKit
import Testing

@testable import ScholiumApp
@testable import ScholiumEditor

@Suite("Native inline writing preview", .serialized)
@MainActor
struct NativeInlineGhostTests {
    @Test("Prose and Callout body admit AI, while structural and finished lines do not")
    func aiAdmission() {
        #expect(NativeEditorInteractions.aiEligible(prefix: "这段论证仍然", next: nil))
        #expect(NativeEditorInteractions.aiEligible(prefix: "> 这段论证仍然", next: 10))
        #expect(!NativeEditorInteractions.aiEligible(prefix: "> [!WARNING] 注意", next: nil))
        #expect(!NativeEditorInteractions.aiEligible(prefix: "# 这段论证仍然", next: nil))
        #expect(!NativeEditorInteractions.aiEligible(prefix: "这段论证已经完成。", next: nil))
        #expect(!NativeEditorInteractions.aiEligible(prefix: "这段论证仍然", next: 65))
    }

    @Test("Escaped library punctuation keeps visible and source prefixes aligned")
    func escapedTerm() {
        let units = NativeEditorInteractions.visibleSourceUnits(#"\-term"#)
        #expect(String(units.map(\.visible)) == "-term")
        #expect(units.prefix(1).map(\.source).joined() == #"\-"#)
        #expect(units.prefix(3).map(\.source).joined() == #"\-te"#)
    }

    @Test("Preview and elision never enter source or selection; composition clears it")
    func displayOnlyAndComposition() throws {
        _ = NSApplication.shared
        let view = EditorTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 240))
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            window.contentView = nil
            window.close()
        }
        view.loadContent("hello")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        window.makeKeyAndOrderFront(nil)
        let source = view.rawSource
        let storage = view.textStorage?.string
        let selection = view.selectedRange()
        let revision = view.sourceState.revision
        let full = String(repeating: " continuation", count: 30)
        let visible = try #require(view.showInlineGhost(full, at: 5, isAI: true))
        #expect(visible.count < full.count)
        #expect(view.hasInlineGhost)
        #expect(view.rawSource == source)
        #expect(view.textStorage?.string == storage)
        #expect(view.selectedRange() == selection)
        #expect(view.sourceState.revision == revision)
        view.setMarkedText(
            "中", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasInlineGhost)
    }
}
