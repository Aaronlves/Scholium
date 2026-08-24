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

    @Test("Scalar encoding preserves literal quotes, indicators, Unicode, and whitespace")
    func scalarEncodingPreservesRequestedSemantics() throws {
        let values = [
            "\"Theory\"",
            "'practice'",
            "@archive",
            "%TAG",
            "!important",
            "&anchor-like",
            "*alias-like",
            "| block-like",
            "> folded-like",
            "`code-like`",
            "- list-like",
            "? question-like",
            "2025-01-01",
            "2025-01-01T14:30:45Z",
            "2025-1-1 9:30:45+08:00",
            "yes",
            "ON",
            "  理论 😀  ",
            "line one\nline two\tend",
        ]

        for value in values {
            let document = NoteDocument(
                relativePath: "scalar.md",
                rawContent: "---\ncustom: old\n---\n"
            )
            let result = try document.applying(
                .frontmatter(["custom": .string(value)]),
                timestampKey: nil
            )
            #expect(NoteDocument(relativePath: "scalar.md", rawContent: result)
                .parsedFrontmatter["custom"] == .string(value))
        }
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

    @Test("An unclosed frontmatter boundary refuses every targeted body replacement")
    func unclosedFrontmatterRefusesTargetedBodyReplacement() {
        let source = "\u{FEFF}---\r\ntitle: Unclosed\r\n# Not a proven body\r\n"
        let document = NoteDocument(
            relativePath: "topics/unclosed.md",
            rawContent: source
        )

        #expect(throws: VaultRepositoryError.self) {
            try document.applying(
                .body("Replacement\r\n"),
                timestampKey: nil
            )
        }
        #expect(throws: VaultRepositoryError.self) {
            try document.applying(
                .composite(body: "Replacement\r\n", frontmatter: [:]),
                timestampKey: nil
            )
        }
        #expect(document.rawContent == source)
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("A closed malformed envelope still permits an exact body-only replacement")
    func closedMalformedFrontmatterPreservesEnvelopeDuringBodyReplacement() throws {
        let source = "---\ntags: [unfinished\n---\nOld body\n"
        let document = NoteDocument(
            relativePath: "topics/closed-malformed.md",
            rawContent: source
        )

        let result = try document.applying(
            .body("New body\n"),
            timestampKey: nil
        )

        #expect(result == "---\ntags: [unfinished\n---\nNew body\n")
    }

    @Test("No-frontmatter body edits do not introduce frontmatter")
    func plainMarkdown() throws {
        let document = NoteDocument(relativePath: "output/plain.md", rawContent: "# Original\n")
        let result = try document.applying(.body("# Changed\n"), timestampKey: nil)
        #expect(result == "# Changed\n")
    }

    @Test("Exact empty-body and body-start semantics are independent of source byte count")
    func exactBodyBoundary() {
        let headerOnly = NoteDocument(
            relativePath: "papers/header.md",
            rawContent: "---\ntags: [draft]\n---\n"
        )
        #expect(headerOnly.hasExactEmptyBody)
        #expect(headerOnly.bodyUTF16Offset == headerOnly.rawContent.utf16.count)

        let whitespaceBody = NoteDocument(
            relativePath: "papers/space.md",
            rawContent: "---\ntags: [draft]\n---\n \n"
        )
        #expect(!whitespaceBody.hasExactEmptyBody)

        let blockScalarDelimiter = NoteDocument(
            relativePath: "papers/block-scalar.md",
            rawContent: "---\ncustom: |+\n  before\n  ---\n  after\n---\n"
        )
        #expect(blockScalarDelimiter.validationWarnings.isEmpty)
        #expect(blockScalarDelimiter.hasExactEmptyBody)
        #expect(blockScalarDelimiter.rawFrontmatter?.contains("  ---\n") == true)
        #expect(
            blockScalarDelimiter.bodyUTF16Offset
                == blockScalarDelimiter.rawContent.utf16.count
        )

        let nonbreakingSpaceOpening = NoteDocument(
            relativePath: "papers/not-frontmatter.md",
            rawContent: "---\u{00A0}\nkey: value\n---\n"
        )
        #expect(nonbreakingSpaceOpening.rawFrontmatter == nil)
        #expect(nonbreakingSpaceOpening.body == nonbreakingSpaceOpening.rawContent)

        let malformedEnvelope = NoteDocument(
            relativePath: "papers/malformed.md",
            rawContent: "---\ntags: [draft]\n"
        )
        #expect(malformedEnvelope.rawFrontmatter == nil)
        #expect(!malformedEnvelope.hasExactEmptyBody)
        #expect(malformedEnvelope.bodyUTF16Offset == 0)

        for malformed in [
            "---\ntags: [\n---\n",
            "---\n- sequence root\n---\n",
            "---\nscalar root\n---\n",
        ] {
            let document = NoteDocument(
                relativePath: "papers/closed-malformed.md",
                rawContent: malformed
            )
            #expect(document.body.isEmpty)
            #expect(!document.validationWarnings.isEmpty)
            #expect(!document.hasExactEmptyBody)
        }
    }

    @Test("Explicit first YAML insertion preserves BOM, newline style, body, and final newline")
    func explicitFirstFrontmatterInsertion() throws {
        let source = "\u{FEFF}# Existing body\r\n\r\nExact tail"
        let document = NoteDocument(
            relativePath: "topics/plain.md",
            rawContent: source
        )
        let result = try document.applying(
            .insertFrontmatter([
                "summary": .string("First: property")
            ]),
            timestampKey: nil
        )
        #expect(
            result
                == "\u{FEFF}---\r\nsummary: \"First: property\"\r\n---\r\n# Existing body\r\n\r\nExact tail"
        )
        let inserted = NoteDocument(
            relativePath: "topics/plain.md",
            rawContent: result
        )
        #expect(inserted.body == "# Existing body\r\n\r\nExact tail")
        #expect(inserted.validationWarnings.isEmpty)

        #expect(throws: VaultRepositoryError.self) {
            try document.applying(
                .insertFrontmatter(["summary": .remove]),
                timestampKey: nil
            )
        }
        #expect(throws: VaultRepositoryError.self) {
            try inserted.applying(
                .insertFrontmatter(["tags": .array(["later"])]),
                timestampKey: nil
            )
        }

        for malformed in [
            "---\nkey: value\n",
            "\u{FEFF}---\r\nkey: value\r\n",
        ] {
            let malformedDocument = NoteDocument(
                relativePath: "topics/malformed.md",
                rawContent: malformed
            )
            #expect(throws: VaultRepositoryError.self) {
                try malformedDocument.applying(
                    .insertFrontmatter(["summary": .string("Do not insert")]),
                    timestampKey: nil
                )
            }
            #expect(malformedDocument.rawContent == malformed)
        }
    }

    @Test("Frontmatter state distinguishes YAML-free source from malformed boundaries")
    func frontmatterStateDistinguishesInsertionSafety() {
        #expect(NoteDocument(relativePath: "plain.md", rawContent: "Body\n").frontmatterState == .absent)
        #expect(NoteDocument(
            relativePath: "valid.md",
            rawContent: "---\ntags: [one]\n---\nBody\n"
        ).frontmatterState == .valid)
        #expect(NoteDocument(
            relativePath: "unclosed.md",
            rawContent: "---\ntags: [one]\n"
        ).frontmatterState == .malformed)
        #expect(NoteDocument(
            relativePath: "closed-invalid.md",
            rawContent: "---\ntags: [\n---\n"
        ).frontmatterState == .malformed)
    }

    @Test("Creator sequences serialize as mappings without changing neighboring bytes")
    func creatorSequenceTargetedEdit() throws {
        let source = "---\n# keep\ntitle: Exact\nauthors:\n  - family: Old\ncustom: 'literal'\n---\nBody\n"
        let document = NoteDocument(relativePath: "analysis.md", rawContent: source)
        let result = try document.applying(.frontmatter([
            "authors": .sequence([
                .mapping([
                    "family": .string("Tappolet"),
                    "given": .string("Christine"),
                ]),
                .mapping(["literal": .string("World Health Organization")]),
            ]),
        ]), timestampKey: nil)

        #expect(result.contains("# keep\n"))
        #expect(result.contains("custom: 'literal'\n"))
        #expect(result.contains("authors:\n  -\n    family: Tappolet\n    given: Christine\n"))
        #expect(result.contains("  -\n    literal: World Health Organization\n"))
        let reparsed = NoteDocument(relativePath: "analysis.md", rawContent: result)
        #expect(reparsed.validationWarnings.isEmpty)
        #expect(reparsed.body == "Body\n")
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
