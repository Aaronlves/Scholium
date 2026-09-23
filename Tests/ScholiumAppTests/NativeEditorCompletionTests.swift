import Foundation
import Testing

@testable import ScholiumApp

@Suite("Native completion exact replacements")
struct NativeEditorCompletionTests {
    @Test("Wikilink aliases consume auto-paired closing brackets without changing adjacent source")
    func pairedLink() throws {
        let source = "前文 [[Ph]] tail"
        let candidate = EditorLinkCompletion(label: "Alias", insertion: "Topic/Philosophy", detail: "", path: "", displayText: "别名", isAmbiguous: false)
        let edit = try NativeEditorCompletion.edit(candidate, kind: .wikilink, queryRange: NSRange(location: 3, length: 4), source: source)
        #expect((source as NSString).replacingCharacters(in: edit.range, with: edit.insertion) == "前文 [[Topic/Philosophy|别名]] tail")
    }

    @Test("Continuation inserts at the caret; library words replace their exact prefix")
    func continuationAndTerm() throws {
        let source = "😀 phil"
        var candidate = EditorLinkCompletion(
            label: "philosophy", insertion: "philosophy", detail: "", path: "", displayText: nil, isAmbiguous: false, replacementUTF16Count: 4)
        let term = try NativeEditorCompletion.edit(candidate, kind: .term, queryRange: NSRange(location: 3, length: 4), source: source)
        #expect((source as NSString).replacingCharacters(in: term.range, with: term.insertion) == "😀 philosophy")
        candidate.replacementUTF16Count = 0
        candidate = .init(label: "osophy", insertion: "osophy", detail: "", path: "", displayText: nil, isAmbiguous: false, replacementUTF16Count: 0)
        let continuation = try NativeEditorCompletion.edit(candidate, kind: .term, queryRange: NSRange(location: 3, length: 4), source: source)
        #expect(continuation.range == NSRange(location: 7, length: 0))
    }

    @Test("Ambiguous targets and invalid scalar boundaries are rejected")
    func rejectedCandidates() {
        let candidate = EditorLinkCompletion(label: "x", insertion: "x", detail: "", path: "", displayText: nil, isAmbiguous: true)
        #expect(throws: (any Error).self) {
            try NativeEditorCompletion.edit(candidate, kind: .wikilink, queryRange: NSRange(location: 0, length: 0), source: "")
        }
        let prefix = EditorLinkCompletion(label: "x", insertion: "x", detail: "", path: "", displayText: nil, isAmbiguous: false, replacementUTF16Count: 1)
        #expect(throws: (any Error).self) { try NativeEditorCompletion.edit(prefix, kind: .term, queryRange: NSRange(location: 2, length: 0), source: "😀") }
    }
}
