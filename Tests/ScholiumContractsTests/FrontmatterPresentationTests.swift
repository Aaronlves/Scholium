import Foundation
import ScholiumContracts
import Testing

@Suite("Frontmatter presentation parity")
struct FrontmatterPresentationTests {
    @Test("Shared fixtures match Review's bounded lexical projection")
    func sharedFixturesMatchReviewProjection() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "frontmatter-presentation-fixtures",
                withExtension: "json",
                subdirectory: "Fixtures"
            ))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))

        for fixture in fixtures {
            let lines = FrontmatterPresentation.lines(in: fixture.frontmatter)
            #expect(lines.count == fixture.lines.count, "Fixture: \(fixture.name)")
            for (actual, expected) in zip(lines, fixture.lines) {
                #expect(actual.text == expected.text, "Fixture: \(fixture.name)")
                switch (actual.role, expected.role) {
                case (.blank, "blank"):
                    break
                case (.comment, "comment"):
                    break
                case (.mapping(_, _, let valueKind), "mapping"):
                    #expect(valueKind.rawValue == expected.valueKind, "Fixture: \(fixture.name)")
                case (.value(let valueKind), "value"):
                    #expect(valueKind.rawValue == expected.valueKind, "Fixture: \(fixture.name)")
                default:
                    Issue.record("Unexpected Review role for \(expected.text) in \(fixture.name)")
                }
            }
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let frontmatter: String
        let lines: [Line]
    }

    private struct Line: Decodable {
        let text: String
        let role: String
        let valueKind: String
        let editorClasses: [String]
    }
}
