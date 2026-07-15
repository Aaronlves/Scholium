import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Research Unit declarations")
struct ResearchUnitTests {
    @Test("A missing Research Unit remains an explicit undeclared state")
    func absentDeclaration() {
        let declaration = ResearchUnitDeclaration(frontmatter: [
            "title": .string("A note")
        ])

        #expect(declaration.state == .absent)
        #expect(declaration.scope == nil)
        #expect(declaration.limitations.isEmpty)
        #expect(!declaration.isInvalid)
    }

    @Test("A valid declaration exposes scope first and preserves its limitations")
    func validDeclaration() {
        let declaration = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .object([
                "scope": .string("Introduction and Chapters 1–4"),
                "limitations": .array([
                    .string("Chapters 5–8 have not been analyzed."),
                    .string("The appendix is outside this note's scope.")
                ])
            ])
        ])

        #expect(declaration.state == .declared)
        #expect(declaration.isDeclared)
        #expect(declaration.scope == "Introduction and Chapters 1–4")
        #expect(declaration.limitations == [
            "Chapters 5–8 have not been analyzed.",
            "The appendix is outside this note's scope."
        ])
    }

    @Test("A declaration without a non-empty scope is invalid")
    func missingScope() {
        let declaration = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .object([
                "limitations": .array([.string("The appendix is outside scope.")])
            ])
        ])

        #expect(declaration.state == .invalid("Scope is required and cannot be empty."))
        #expect(declaration.validationMessage == "Scope is required and cannot be empty.")
    }

    @Test("Empty or malformed limitations are invalid rather than silently discarded")
    func malformedLimitations() {
        let empty = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .object([
                "scope": .string("A bounded scope"),
                "limitations": .array([])
            ])
        ])
        let nonText = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .object([
                "scope": .string("A bounded scope"),
                "limitations": .array([.integer(3)])
            ])
        ])

        #expect(empty.isInvalid)
        #expect(nonText.validationMessage == "Each limitation must be a non-empty text value.")
    }

    @Test("Unknown fields and scalar Research Units are rejected")
    func unsupportedShape() {
        let unknownField = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .object([
                "scope": .string("A bounded scope"),
                "confidence": .string("high")
            ])
        ])
        let scalar = ResearchUnitDeclaration(frontmatter: [
            "research_unit": .string("A bounded scope")
        ])

        #expect(unknownField.validationMessage == "Unsupported field: confidence.")
        #expect(scalar.validationMessage == "Research Status must be a mapping.")
    }
}
