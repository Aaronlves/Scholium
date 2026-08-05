import Foundation
import Testing
import ScholiumContracts
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

    @Test("Canonical summary shares the exact targeted YAML write path")
    func canonicalSummaryPreservesUnknownYAMLAndBody() throws {
        let source = "\u{FEFF}---\r\n# researcher context\r\nsummary: Old map   # keep attribution-adjacent comment\r\nunknown:\r\n  nested: 'exact value'\r\n---\r\n# Body 😀\r\n\r\nUnchanged evidence."
        let document = NoteDocument(relativePath: "Topics/Map.md", rawContent: source)
        let result = try document.applying(
            .frontmatter(["summary": .string("Agent-refined: claim remains contested")]),
            timestampKey: nil
        )

        #expect(result == "\u{FEFF}---\r\n# researcher context\r\nsummary: \"Agent-refined: claim remains contested\"   # keep attribution-adjacent comment\r\nunknown:\r\n  nested: 'exact value'\r\n---\r\n# Body 😀\r\n\r\nUnchanged evidence.")
        #expect(NoteDocument(relativePath: "Topics/Map.md", rawContent: result).body == document.body)
    }

    @Test("Scalar patches preserve BOM, CRLF, inline comments, and body final-newline state")
    func scalarPatchPreservesExactSurroundings() throws {
        let source = "\u{FEFF}---\r\n# before\r\ntitle: Old value   # keep inline\r\ncustom:\r\n  nested: true\r\n---\r\nBody without final newline"
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: source)
        let result = try document.applying(
            .frontmatter(["title": .string("New: value")]),
            timestampKey: nil
        )

        #expect(result == "\u{FEFF}---\r\n# before\r\ntitle: \"New: value\"   # keep inline\r\ncustom:\r\n  nested: true\r\n---\r\nBody without final newline")
        #expect(!result.hasSuffix("\n"))
    }

    @Test("A missing key appends only inside a proven block mapping")
    func safeAppend() throws {
        let source = "---\ntitle: Existing\ncustom:\n  nested: true\n---\nBody\n"
        let document = NoteDocument(relativePath: "topics/a.md", rawContent: source)
        let result = try document.applying(
            .frontmatter(["status": .string("candidate")]),
            timestampKey: nil
        )
        #expect(result == "---\ntitle: Existing\ncustom:\n  nested: true\nstatus: candidate\n---\nBody\n")
    }

    @Test("Ambiguous YAML constructs refuse without producing replacement bytes", arguments: [
        "\"title\": Old\n",
        "title: One\ntitle: Two\n",
        "base: &base value\ntitle: *base\n",
        "base: &base\n  title: Old\n<<: *base\n",
        "{title: Old, custom: true}\n",
        "title: |\n  Old value\n",
        "title: Old value\n  continued value\n",
    ])
    func ambiguousYAMLRefuses(frontmatter: String) {
        #expect(throws: FrontmatterPatchRefusal.self) {
            _ = try FrontmatterPatchPlanner.plan(
                frontmatter: frontmatter,
                edits: ["title": .string("New")],
                newline: "\n"
            )
        }
    }

    @Test("A bounded mapping edit preserves unrelated members and source bytes")
    func boundedMappingEdit() throws {
        let source = "---\n# keep this comment\ntitle: Old\nresearch_unit:\n  scope: Old scope\n  limitations:\n    - Old boundary\ncustom:\n  nested: true\n---\nBody\n"
        let document = NoteDocument(relativePath: "papers/a.md", rawContent: source)
        let result = try document.applying(
            .frontmatter([
                "research_unit": .mapping([
                    "scope": .string("Introduction and Chapters 1–4"),
                    "limitations": .array(["Chapters 5–8 remain outside the note."])
                ])
            ]),
            timestampKey: nil
        )

        #expect(result.contains("# keep this comment\ntitle: Old\n"))
        #expect(result.contains("research_unit:\n  scope: Introduction and Chapters 1–4\n  limitations:\n    - Chapters 5–8 remain outside the note.\n"))
        #expect(result.contains("custom:\n  nested: true\n"))
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
