import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Role-aware Research Unit declarations")
struct ResearchUnitTests {
    @Test("A missing Research Unit is valid and absent for every role")
    func absentDeclaration() {
        for profile in [
            SchemaProfileID.analysis,
            .topicMarkdown,
            .draftProject,
        ] {
            let declaration = ResearchUnitDeclaration(
                frontmatter: ["title": .string("A note")],
                profile: profile
            )
            #expect(declaration.state == .absent)
            #expect(declaration.completion == nil)
            #expect(declaration.scope == nil)
            #expect(declaration.limitations.isEmpty)
        }
    }

    @Test("Analysis accepts binary, ratio, and limitation-only declarations")
    func analysisForms() {
        for (value, expected) in [
            ("complete", AnalysisCompletion.complete),
            ("incomplete", .incomplete),
            ("0/1", .represented(completed: 0, total: 1)),
            ("6/11", .represented(completed: 6, total: 11)),
            ("11/11", .represented(completed: 11, total: 11)),
        ] {
            let declaration = ResearchUnitDeclaration(
                frontmatter: [
                    "research_unit": .object(["completion": .string(value)])
                ],
                profile: .analysis
            )
            #expect(declaration.state == .declared)
            #expect(declaration.completion == expected)
            #expect(declaration.scope == nil)
        }

        let limitationOnly = ResearchUnitDeclaration(
            frontmatter: [
                "research_unit": .object([
                    "limitations": .array([.string("Only one translation was used.")])
                ])
            ],
            profile: .analysis
        )
        #expect(limitationOnly.state == .declared)
        #expect(limitationOnly.completion == nil)
        #expect(limitationOnly.limitations == ["Only one translation was used."])
    }

    @Test("Analysis rejects invalid ratios, wrong types, and Scope")
    func invalidAnalysisForms() {
        for value in ["1/0", "-1/3", "4/3", "1/", "/2", "one/two"] {
            let declaration = ResearchUnitDeclaration(
                frontmatter: [
                    "research_unit": .object(["completion": .string(value)])
                ],
                profile: .analysis
            )
            #expect(declaration.isInvalid, "Expected invalid ratio \(value)")
        }
        let numeric = ResearchUnitDeclaration(
            frontmatter: [
                "research_unit": .object(["completion": .integer(6)])
            ],
            profile: .analysis
        )
        #expect(numeric.validationMessage == "Completion must be complete, incomplete, or a valid completed/total ratio.")

        let scope = ResearchUnitDeclaration(
            frontmatter: [
                "research_unit": .object(["scope": .string("Chapters 1–6")])
            ],
            profile: .analysis
        )
        #expect(scope.validationMessage == "Unsupported field: scope.")
    }

    @Test("Topic and Work accept Scope, Limitations, or both")
    func topicAndWorkForms() {
        for profile in [SchemaProfileID.topicMarkdown, .draftProject] {
            let scopeOnly = ResearchUnitDeclaration(
                frontmatter: [
                    "research_unit": .object(["scope": .string("  A bounded question  ")])
                ],
                profile: profile
            )
            #expect(scopeOnly.state == .declared)
            #expect(scopeOnly.scope == "A bounded question")

            let limitationOnly = ResearchUnitDeclaration(
                frontmatter: [
                    "research_unit": .object([
                        "limitations": .array([.string("A historical variant is excluded.")])
                    ])
                ],
                profile: profile
            )
            #expect(limitationOnly.state == .declared)
            #expect(limitationOnly.scope == nil)

            let both = ResearchUnitDeclaration(
                frontmatter: [
                    "research_unit": .object([
                        "scope": .string("A bounded question"),
                        "limitations": .array([.string("One archive is unavailable.")]),
                    ])
                ],
                profile: profile
            )
            #expect(both.state == .declared)
            #expect(both.limitations == ["One archive is unavailable."])
        }
    }

    @Test("Empty, unknown, cross-role, and malformed structures fail closed")
    func unsupportedShapes() {
        let empty = ResearchUnitDeclaration(
            frontmatter: ["research_unit": .object([:])],
            profile: .topicMarkdown
        )
        #expect(empty.validationMessage == "research_unit must contain at least one non-empty member.")

        let unknown = ResearchUnitDeclaration(
            frontmatter: [
                "research_unit": .object([
                    "scope": .string("A bounded scope"),
                    "confidence": .string("high"),
                ])
            ],
            profile: .topicMarkdown
        )
        #expect(unknown.validationMessage == "Unsupported field: confidence.")

        let crossRole = ResearchUnitDeclaration(
            frontmatter: [
                "research_unit": .object(["completion": .string("complete")])
            ],
            profile: .draftProject
        )
        #expect(crossRole.validationMessage == "Unsupported field: completion.")

        let scalar = ResearchUnitDeclaration(
            frontmatter: ["research_unit": .string("A bounded scope")],
            profile: .topicMarkdown
        )
        #expect(scalar.validationMessage == "research_unit must be a mapping.")
    }
}
