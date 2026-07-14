import Foundation
import Testing
@testable import ScholiumCore

@Suite("Lossless note documents")
struct NoteDocumentTests {
    @Test("Body edits preserve frontmatter bytes and CRLF")
    func bodyPreservation() throws {
        let source = "\u{FEFF}---\r\ntitle: \"A: title\" # keep\r\nnested:\r\n  key: value\r\ntags: [one, \"two, three\"]\r\nanalysis_updated_at: 2025-01-01\r\n---\r\n# Old\r\n\r\nTail\r\n"
        let document = NoteDocument(relativePath: "papers/a.md", rawContent: source)
        let result = try document.applying(.body("# New\r\n\r\nTail\r\n"), timestampKey: nil)

        #expect(document.sourceBytes == Data(source.utf8))
        #expect(document.frontmatterByteRange != nil)
        #expect(document.bodyByteRange.upperBound == document.sourceBytes.count)
        #expect(result.hasPrefix("\u{FEFF}---\r\ntitle: \"A: title\" # keep\r\nnested:\r\n  key: value\r\ntags: [one, \"two, three\"]\r\nanalysis_updated_at: 2025-01-01\r\n---\r\n"))
        #expect(result.hasSuffix("# New\r\n\r\nTail\r\n"))
    }

    @Test("A frontmatter edit changes only its top-level field")
    func targetedFrontmatterEdit() throws {
        let source = "---\n# comment\ntitle: Old\ncustom:\n  nested: true\ntags:\n  - a\n  - b\n---\nBody\n"
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: source)
        let result = try document.applying(
            .frontmatter(["title": .string("New: title")]),
            timestampKey: nil
        )

        #expect(result.contains("# comment\ntitle: \"New: title\"\ncustom:\n  nested: true\ntags:\n  - a\n  - b\n"))
        #expect(result.hasSuffix("---\nBody\n"))
    }

    @Test("Malformed YAML remains readable but cannot be metadata-edited")
    func malformedYAML() {
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: "---\ntags: [one, two\n---\nBody")
        #expect(!document.validationWarnings.isEmpty)
        #expect(throws: VaultRepositoryError.self) {
            try document.applying(.frontmatter(["title": .string("X")]), timestampKey: nil)
        }
    }

    @Test("No-frontmatter body edits do not introduce frontmatter")
    func plainMarkdown() throws {
        let document = NoteDocument(relativePath: "output/plain.md", rawContent: "# Original\n")
        let result = try document.applying(.body("# Changed\n"), timestampKey: nil)
        #expect(result == "# Changed\n")
    }

    @Test("Source mode edits the complete document and targets only the save timestamp")
    func completeSourceEdit() throws {
        let original = "\u{FEFF}---\r\n# keep\r\ntitle: Old\r\ncustom: \"a: b\"\r\nmodified: 2025-01-01\r\n---\r\n# Original\r\n"
        let edited = "\u{FEFF}---\r\n# keep\r\ntitle: New\r\ncustom: \"a: b\"\r\nmodified: 2025-01-01\r\n---\r\n# Changed\r\n"
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: original)
        let result = try document.applying(.source(edited), timestampKey: "modified", timestamp: timestamp)

        #expect(result.hasPrefix("\u{FEFF}---\r\n# keep\r\ntitle: New\r\ncustom: \"a: b\"\r\n"))
        #expect(result.contains("modified: \"2023-11-14T22:13:20Z\"\r\n"))
        #expect(result.hasSuffix("---\r\n# Changed\r\n"))
    }

    @Test("Source mode rejects malformed frontmatter")
    func malformedSourceEdit() {
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: "---\ntitle: Valid\n---\nBody\n")
        #expect(throws: VaultRepositoryError.self) {
            try document.applying(.source("---\ntags: [one, two\n---\nBody\n"), timestampKey: "modified")
        }
    }
}
