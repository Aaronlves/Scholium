import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Note Info exact authored metadata")
struct NoteInfoMetadataPlannerTests {
    @Test("PDF binding is an exact authored string, never an inferred relation")
    func exactPDFBinding() throws {
        let document = NoteDocument(relativePath: "Nested/Note.md", rawContent: "---\npdf: '../../.scholium/attachments/files/a/Paper.pdf' # own\n---\nBody")
        #expect(try PDFNoteBinding.path(in: document) == "../../.scholium/attachments/files/a/Paper.pdf")
        #expect(try PDFNoteBinding.path(in: NoteDocument(relativePath: "Note.md", rawContent: "Body")) == nil)
        #expect(try PDFNoteBinding.path(in: NoteDocument(relativePath: "Note.md", rawContent: "---\npdf: ''\n---\nBody")) == nil)
        #expect(try PDFNoteBinding.path(in: NoteDocument(relativePath: "Note.md", rawContent: "---\npdf: null\n---\nBody")) == nil)
    }

    @Test(
        "Ambiguous or non-string pdf does not authorize an attachment",
        arguments: [
            "---\npdf: [a.pdf]\n---\nBody", "---\npdf: one.pdf\npdf: two.pdf\n---\nBody",
            "---\npdf: |\n  first.pdf\n  second.pdf\n---\nBody",
            "---\npdf: [unfinished\n---\nBody", "---\npdf: missing-close.pdf\nBody",
        ])
    func invalidPDFBinding(_ source: String) {
        #expect(throws: NoteInfoMetadataError.self) {
            try PDFNoteBinding.path(in: NoteDocument(relativePath: "Note.md", rawContent: source))
        }
    }

    @Test("Summary and PDF updates preserve unknown bytes, body, BOM and mixed newlines")
    func targetedMetadataPatch() throws {
        let source =
            "\u{FEFF}---\r\n# Keep this\nsummary: 'old' # summary comment\r\ncustom:\n  map: [1, true, 'quoted']\r\nabstract: |-\n  Keep multiline text\r\n---\nBody 😀\r\n"
        let document = NoteDocument(relativePath: "Nested/Note.md", rawContent: source)
        let plan = try #require(
            try NoteInfoMetadataPlanner.plan(
                document: document,
                edits: [
                    "summary": .string("New 😀 summary"), "pdf": .string("../../.scholium/attachments/files/id/Paper.pdf"),
                ]))
        let applied = applying(plan)
        #expect(applied == plan.resultingSource)
        #expect(applied.hasPrefix("\u{FEFF}---\r\n# Keep this\n"))
        #expect(applied.contains(" # summary comment\r\ncustom:\n  map: [1, true, 'quoted']\r\nabstract: |-\n  Keep multiline text\r\n"))
        #expect(applied.hasSuffix("---\nBody 😀\r\n"))
        #expect(NoteDocument(relativePath: "Note.md", rawContent: applied).parsedFrontmatter["summary"] == .string("New 😀 summary"))
        #expect(try PDFNoteBinding.path(in: NoteDocument(relativePath: "Note.md", rawContent: applied)) == "../../.scholium/attachments/files/id/Paper.pdf")
    }

    @Test("Attach explicitly creates first YAML, preserving BOM and final newline style", arguments: ["Body", "\u{FEFF}Body\r\n"])
    func firstYAML(_ source: String) throws {
        let plan = try #require(
            try NoteInfoMetadataPlanner.plan(
                document: .init(relativePath: "Note.md", rawContent: source), edits: ["pdf": .string("../.scholium/attachments/files/id/P.pdf")]))
        #expect(applying(plan) == plan.resultingSource)
        #expect(plan.resultingSource.hasSuffix(source.replacingOccurrences(of: "\u{FEFF}", with: "")))
        #expect(plan.resultingSource.unicodeScalars.first?.value == source.unicodeScalars.first?.value || !source.hasPrefix("\u{FEFF}"))
    }

    @Test("Detach changes only the authored binding and never consumes other keys")
    func detach() throws {
        let source = "---\nunknown: keep\npdf: 'Paper.pdf' # binding\n# Preserve following comment\ntags: [one, two]\n---\nBody"
        let plan = try #require(try NoteInfoMetadataPlanner.plan(document: .init(relativePath: "Note.md", rawContent: source), edits: ["pdf": .remove]))
        #expect(applying(plan) == "---\nunknown: keep\n# Preserve following comment\ntags: [one, two]\n---\nBody")
        #expect(try NoteInfoMetadataPlanner.plan(document: .init(relativePath: "Note.md", rawContent: "Body"), edits: ["pdf": .remove]) == nil)
    }

    @Test(
        "An empty null PDF binding accepts a scalar without consuming whitespace or its comment",
        arguments: [
            ("pdf:", "pdf: Paper.pdf"),
            ("pdf:   ", "pdf: Paper.pdf   "),
            ("pdf:  # exact comment", "pdf: Paper.pdf  # exact comment"),
        ])
    func bindEmptyNull(_ original: String, _ expected: String) throws {
        let source = "\u{FEFF}---\r\nkeep: 'authored'\r\n\(original)\r\nunknown: {nested: true}\r\n---\r\nBody"
        let document = NoteDocument(relativePath: "Note.md", rawContent: source)
        #expect(try PDFNoteBinding.path(in: document) == nil)
        let plan = try #require(try NoteInfoMetadataPlanner.plan(document: document, edits: ["pdf": .string("Paper.pdf")]))
        #expect(applying(plan) == source.replacingOccurrences(of: original + "\r\n", with: expected + "\r\n"))
        #expect(try PDFNoteBinding.path(in: .init(relativePath: "Note.md", rawContent: plan.resultingSource)) == "Paper.pdf")
    }

    @Test("Unbounded YAML is refused without a substitute serialization")
    func refusal() {
        let source = "---\npdf: one.pdf\npdf: two.pdf\n---\nBody"
        #expect(throws: (any Error).self) {
            try NoteInfoMetadataPlanner.plan(document: .init(relativePath: "Note.md", rawContent: source), edits: ["pdf": .string("replacement.pdf")])
        }
    }

    private func applying(_ patch: NoteInfoSourcePatch) -> String {
        let source = patch.expectedSource as NSString
        return source.replacingCharacters(in: NSRange(location: patch.fromUTF16, length: patch.toUTF16 - patch.fromUTF16), with: patch.replacement)
    }
}
