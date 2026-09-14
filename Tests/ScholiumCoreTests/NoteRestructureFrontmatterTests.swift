import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

struct NoteRestructureFrontmatterTests {
    private func merge(_ source: String, into target: String, choices: [String: NoteRestructurePropertyResolution] = [:]) throws -> String {
        let edits = try NoteRestructureFrontmatterPlanner.edits(
            source: .init(relativePath: "Source.md", rawContent: source), target: .init(relativePath: "Target.md", rawContent: target), resolutions: choices)
        return edits.isEmpty ? target : try AgentSourceEdit.applying(edits, to: Data(target.utf8))
    }

    @Test func retainsExactAuthoredEntriesAndDestinationBody() throws {
        let source = "---\n# Source context\n'研究 问题': '行动理由' # source\nsummary: |-\n  A precise claim.\nunknown: {nested: [true, 'false', 2]}\n---\nSource body"
        let target = "\u{FEFF}---\r\n# Target context\nkeep: \"untouched\" # exact\r\n---\r\nTarget body\r\n"
        let result = try merge(source, into: target)
        #expect(
            result
                == "\u{FEFF}---\r\n# Target context\nkeep: \"untouched\" # exact\r\n# Source context\n'研究 问题': '行动理由' # source\nsummary: |-\n  A precise claim.\nunknown: {nested: [true, 'false', 2]}\n---\r\nTarget body\r\n"
        )
        let parsed = NoteDocument(relativePath: "Target.md", rawContent: result)
        #expect(parsed.parsedFrontmatter["研究 问题"] == .string("行动理由"))
        #expect(parsed.parsedFrontmatter["summary"] == .string("A precise claim."))
        #expect(parsed.body == "Target body\r\n")
    }

    @Test func conflictsRequireExplicitEntryChoice() throws {
        let source = "---\nstatus: 'draft' # incoming\nextra: true\n---\nSource"
        let target = "---\nstatus: final # current\nkeep: 42\n---\nTarget"
        do {
            _ = try merge(source, into: target)
            Issue.record("Conflicting properties must not select a value automatically")
        } catch NoteRestructureError.propertyConflicts(let conflicts) {
            #expect(conflicts == [.init(key: "status", sourceEntry: "status: 'draft' # incoming\n", destinationEntry: "status: final # current\n")])
        }
        #expect(try merge(source, into: target, choices: ["status": .keepDestination]) == "---\nstatus: final # current\nkeep: 42\nextra: true\n---\nTarget")
        #expect(try merge(source, into: target, choices: ["status": .useSource]) == "---\nstatus: 'draft' # incoming\nkeep: 42\nextra: true\n---\nTarget")
    }

    @Test func identicalEntriesAndSourceWithoutPropertiesAreNoOps() throws {
        let target = "---\nkey: 'value'\n---\nTarget"
        #expect(try merge("---\nkey: 'value'\n---\nSource", into: target) == target)
        #expect(try merge("Source", into: target) == target)
    }

    @Test func addsEnvelopeAfterBOMWithoutChangingBody() throws {
        let target = "\u{FEFF}Target\r\nNo final newline"
        #expect(try merge("---\nkey: 'value'\n---\nSource", into: target) == "\u{FEFF}---\r\nkey: 'value'\n---\r\nTarget\r\nNo final newline")
    }

    @Test(arguments: [
        "---\nkey: 1\nkey: 2\n---\nBody", "---\nkey: [\n---\nBody", "---\n{key: value}\n---\nBody",
        "---\nkey: &base value\nother: *base\n---\nBody", "---\nkey: {a: 1, a: 2}\n---\nBody",
        "---\nkey: value\nBody", "---\n? complex\n: value\n---\nBody",
    ])
    func refusesUnprovablePropertyTransfers(_ source: String) throws {
        #expect(throws: NoteRestructureError.self) { try merge(source, into: "Target") }
    }

    @Test func retainsCommentsOnlyFrontmatter() throws {
        #expect(try merge("---\n# Read this first\n---\nSource", into: "Target") == "---\n# Read this first\n---\nTarget")
    }

    @Test func keepingDestinationPreservesSourceCommentsBeforeUnrelatedKeyAndAtEnd() throws {
        let source =
            "---\r\nstatus: draft # incoming\r\n\r\n# Cite the first edition only\r\ncitation: 'Author 1900'\r\n  # Source trailing context\r\n---\r\nSource"
        let target = "\u{FEFF}---\nstatus: final # current\n# Destination trailing context\n---\nTarget"
        let result = try merge(source, into: target, choices: ["status": .keepDestination])
        #expect(
            result
                == "\u{FEFF}---\nstatus: final # current\n# Destination trailing context\n\r\n# Cite the first edition only\r\ncitation: 'Author 1900'\r\n  # Source trailing context\r\n---\nTarget"
        )
        let parsed = NoteDocument(relativePath: "Target.md", rawContent: result)
        #expect(parsed.parsedFrontmatter["status"] == .string("final"))
        #expect(parsed.parsedFrontmatter["citation"] == .string("Author 1900"))
        #expect(parsed.body == "Target")
    }

    @Test func usingSourcePreservesDestinationCommentsBeforeUnrelatedKey() throws {
        let source = "---\nstatus: draft # incoming\n# Source context\n---\nSource"
        let target = "---\r\nstatus: final # current\r\n\r\n# Cite the first edition only\r\ncitation: 'Author 1900'\r\n# Target context\r\n---\r\nTarget"
        let result = try merge(source, into: target, choices: ["status": .useSource])
        #expect(
            result
                == "---\r\nstatus: draft # incoming\n\r\n# Cite the first edition only\r\ncitation: 'Author 1900'\r\n# Target context\r\n# Source context\n---\r\nTarget"
        )
        let parsed = NoteDocument(relativePath: "Target.md", rawContent: result)
        #expect(parsed.parsedFrontmatter["status"] == .string("draft"))
        #expect(parsed.parsedFrontmatter["citation"] == .string("Author 1900"))
    }

    @Test func independentCommentsDoNotMakeIdenticalPropertiesConflict() throws {
        let source = "---\nstatus: draft\n# Source context\n---\nSource"
        let target = "---\nstatus: draft\n# Target context\n---\nTarget"
        #expect(try merge(source, into: target) == "---\nstatus: draft\n# Target context\n# Source context\n---\nTarget")
    }

    @Test(arguments: ["|", "|-", "|+", ">", ">-", ">+"])
    func retainsHashContentAndChompingInsideBlockScalars(_ style: String) throws {
        let source = "---\nsummary: \(style)\n  # This is authored scalar content\n\n# Independent source context\nextra: true\n---\nSource"
        let target = "---\nsummary: old\n# Independent target context\n---\nTarget"
        let original = NoteDocument(relativePath: "Source.md", rawContent: source)
        let result = try merge(source, into: target, choices: ["summary": .useSource])
        let parsed = NoteDocument(relativePath: "Target.md", rawContent: result)
        #expect(parsed.parsedFrontmatter["summary"] == original.parsedFrontmatter["summary"])
        #expect(parsed.parsedFrontmatter["extra"] == .boolean(true))
        #expect(result.contains("summary: \(style)\n  # This is authored scalar content\n"))
        #expect(result.contains("# Independent target context\n"))
        #expect(result.contains("# Independent source context\n"))
        #expect(!result.contains("summary: old"))
    }
}
