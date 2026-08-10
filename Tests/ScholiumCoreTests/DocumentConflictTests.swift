import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Document conflict comparison")
struct DocumentConflictTests {
    @Test("Comparison preserves insertions and removals around unchanged lines")
    func alignedComparison() throws {
        let snapshot = DocumentConflictSnapshot(
            relativePath: "Notes/Conflict.md",
            editorSource: "alpha\nlocal\nomega\n",
            diskSource: "disk\nalpha\nomega\nexternal\n",
            baseRevision: DocumentFingerprint(content: "alpha\nomega\n")
        )

        let lines = try snapshot.exactComparison().lines
        #expect(lines.contains { $0.kind == .endingOnly && $0.text == "disk" })
        #expect(lines.contains { $0.kind == .startingOnly && $0.text == "local" })
        #expect(lines.contains { $0.kind == .endingOnly && $0.text == "external" })
        #expect(lines.filter { $0.kind == .unchanged }.map(\.text) == ["alpha", "omega"])
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
    func repeatedLines() throws {
        let snapshot = DocumentConflictSnapshot(
            relativePath: "Repeated.md",
            editorSource: "same\nlocal\nsame",
            diskSource: "same\ndisk\nsame",
            baseRevision: DocumentFingerprint(content: "same\nsame")
        )

        let lines = try snapshot.exactComparison().lines
        let editorOnly = lines.filter { $0.kind == .startingOnly }.map(\.text)
        let diskOnly = lines.filter { $0.kind == .endingOnly }.map(\.text)
        #expect(editorOnly == ["local"])
        #expect(diskOnly == ["disk"])
    }
}
