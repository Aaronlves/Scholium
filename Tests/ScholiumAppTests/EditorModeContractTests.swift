import Foundation
import Testing

@Suite("Three-mode editor contract")
struct EditorModeContractTests {
    private struct Contract: Decodable {
        struct Comparison: Decodable {
            let surface: String
            let classification: String
            let properties: [String]
        }

        let authority: String
        let referenceMode: String
        let comparisons: [Comparison]
        let requiredSourceTokens: [String]
    }

    @Test("The fixed catalog classifies every permitted and forbidden mode difference")
    func fixedCatalogIsCompleteAndAuthorityBound() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = repository.appendingPathComponent("Tests/Fixtures/Editor")
        let sourceURL = fixtureDirectory.appendingPathComponent("three-mode-contract.md")
        let sourceData = try Data(contentsOf: sourceURL)
        let source = try String(
            contentsOf: sourceURL,
            encoding: .utf8
        )
        let contract = try JSONDecoder().decode(
            Contract.self,
            from: Data(contentsOf: fixtureDirectory.appendingPathComponent("three-mode-contract.json"))
        )
        let specification = try String(
            contentsOf: repository.appendingPathComponent(
                "Docs/Specification/02-notes-and-file-operations.md"
            ),
            encoding: .utf8
        )

        #expect(
            contract.authority
                == "Docs/Specification/02-notes-and-file-operations.md section 5.1"
        )
        #expect(contract.referenceMode == "Review")
        #expect(sourceData.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(Set(contract.comparisons.map(\.classification)) == Set([
            "mustMatchReview",
            "permittedEditingDifference",
            "requiredSourceDifference",
            "forbiddenSourceLeak",
            "mustPreserve",
        ]))
        #expect(contract.comparisons.allSatisfy { !$0.surface.isEmpty && !$0.properties.isEmpty })
        for token in contract.requiredSourceTokens {
            #expect(source.contains(token), "Missing fixed editor-contract construct: \(token)")
        }

        let normalizedSpecification = specification
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        #expect(normalizedSpecification.contains(
            "**Edit** modifies the exact body through a reversible semantic projection."
        ))
        #expect(normalizedSpecification.contains(
            "It shares Review typography and components, reveals syntax only for the active construct"
        ))
        #expect(normalizedSpecification.contains(
            "**Source** edits complete Markdown and YAML with logical source-line numbers and exact-source typography."
        ))
        #expect(normalizedSpecification.contains(
            "Review and Edit may differ only where editing requires caret, selection, composition, or active syntax."
        ))
    }
}
