import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Document conflict comparison")
struct DocumentConflictTests {
    @Test("Comparison preserves insertions and removals around unchanged lines")
    func alignedComparison() {
        let snapshot = DocumentConflictSnapshot(
            relativePath: "Notes/Conflict.md",
            editorSource: "alpha\nlocal\nomega\n",
            diskSource: "disk\nalpha\nomega\nexternal\n",
            baseRevision: DocumentFingerprint(content: "alpha\nomega\n")
        )

        #expect(snapshot.comparisonLines == [
            DocumentConflictLine(kind: .diskOnly, text: "disk"),
            DocumentConflictLine(kind: .unchanged, text: "alpha"),
            DocumentConflictLine(kind: .editorOnly, text: "local"),
            DocumentConflictLine(kind: .unchanged, text: "omega"),
            DocumentConflictLine(kind: .diskOnly, text: "external"),
            DocumentConflictLine(kind: .unchanged, text: ""),
        ])
    }

    @Test("Snapshot binds the displayed sources to exact revisions")
    func revisionBinding() {
        let base = DocumentFingerprint(content: "base")
        let snapshot = DocumentConflictSnapshot(
            relativePath: "Conflict.md",
            editorSource: "local",
            diskSource: "external",
            baseRevision: base
        )

        #expect(snapshot.baseRevision == base)
        #expect(snapshot.editorRevision == DocumentFingerprint(content: "local"))
        #expect(snapshot.diskRevision == DocumentFingerprint(content: "external"))
        #expect(snapshot.editorRevision != snapshot.diskRevision)
    }

    @Test("Repeated lines remain represented without dropping source text")
    func repeatedLines() {
        let snapshot = DocumentConflictSnapshot(
            relativePath: "Repeated.md",
            editorSource: "same\nlocal\nsame",
            diskSource: "same\ndisk\nsame",
            baseRevision: DocumentFingerprint(content: "same\nsame")
        )

        let editorOnly = snapshot.comparisonLines.filter { $0.kind == .editorOnly }.map(\.text)
        let diskOnly = snapshot.comparisonLines.filter { $0.kind == .diskOnly }.map(\.text)
        #expect(editorOnly == ["local"])
        #expect(diskOnly == ["disk"])
    }
}
