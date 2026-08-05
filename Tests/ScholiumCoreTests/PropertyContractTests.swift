import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Property contracts")
struct PropertyContractTests {
    @Test("Default Triptych profiles expose the current canonical vocabulary")
    func defaultProfileVocabulary() throws {
        let analysis = PropertyContractCatalog.contracts(for: .analysis)
        let topic = PropertyContractCatalog.contracts(for: .topicMarkdown)
        let work = PropertyContractCatalog.contracts(for: .draftProject)

        #expect(analysis.map(\.canonicalKey) == [
            "title", "summary", "authors", "year", "type", "tags", "research_unit",
            "zotero_item_key", "access", "text_reliability", "locators",
            "debate_importance", "debate_importance_scope",
        ])
        #expect(topic.map(\.canonicalKey) == [
            "summary", "aliases", "tags", "research_unit",
        ])
        #expect(work.map(\.canonicalKey) == [
            "summary", "authors", "kind", "tags", "research_unit", "venue",
        ])

        for profile in [SchemaProfileID.analysis, .topicMarkdown, .draftProject] {
            let summary = try #require(
                PropertyContractCatalog.contract(for: "summary", profile: profile)
            )
            #expect(summary.valueKind == .text)
            #expect(summary.ownership == .researcher)
            #expect(summary.creationRequirement == .optional)
        }

        let researchUnit = try #require(
            PropertyContractCatalog.contract(for: "research_unit", profile: .analysis)
        )
        #expect(researchUnit.valueKind == .mapping)
        #expect(researchUnit.creationRequirement == .optional)
        #expect(analysis.allSatisfy { $0.creationRequirement == .optional })
        #expect(PropertyContractCatalog.contract(
            for: "zotero_item_key",
            profile: .analysis
        )?.ownership == .protectedMachine)
        #expect(PropertyContractCatalog.contract(for: "status", profile: .analysis) == nil)
        #expect(PropertyContractCatalog.contract(for: "deadline", profile: .draftProject) == nil)
        let importance = try #require(
            PropertyContractCatalog.contract(for: "debate_importance", profile: .analysis)
        )
        #expect(importance.constraints.contains(
            .integerRange(minimum: 0, maximum: 10)
        ))
        #expect(importance.constraints.contains(
            .pairedWith(canonicalKey: "debate_importance_scope")
        ))
        #expect(PropertyContractCatalog.contract(
            for: "research_unit",
            profile: .topicMarkdown
        )?.creationRequirement == .optional)
    }

    @Test("Every profile has unique canonical keys and stable indexed lookup")
    func profileKeysAreUniqueAndRoundTripThroughTheIndex() {
        for profile in SchemaProfileID.allCases {
            let contracts = PropertyContractCatalog.contracts(for: profile)
            let keys = contracts.map(\.canonicalKey)
            #expect(Set(keys).count == keys.count, "Duplicate canonical key in \(profile.rawValue)")

            for contract in contracts {
                #expect(PropertyContractCatalog.contract(
                    for: contract.canonicalKey,
                    profile: profile
                ) == contract)
            }
        }
    }

    @Test("Creation requirements remain contextual")
    func creationRequirementsAreContextual() {
        let existing = PropertyContractCatalog.validate(
            frontmatter: [:],
            profile: .analysis,
            context: .existingDocument
        )
        #expect(existing.isEmpty)

        let creation = PropertyContractCatalog.validate(
            frontmatter: [:],
            profile: .analysis,
            context: .creation
        )
        #expect(creation.isEmpty)

        let yamlFreeTopic = NoteDocument(
            relativePath: "Topics/Agency.md",
            rawContent: "# Agency\n"
        )
        #expect(PropertyContractCatalog.validate(
            yamlFreeTopic,
            profile: .topicMarkdown,
            context: .creation
        ).isEmpty)
        #expect(yamlFreeTopic.rawFrontmatter == nil)
        #expect(yamlFreeTopic.rawContent == "# Agency\n")
    }

    @Test("Allowed values and Analysis cross-field rules match the current editor contract")
    func allowedValuesAndAnalysisCrossFields() {
        let invalid = PropertyContractCatalog.validate(
            frontmatter: [
                "type": .string("web_page"),
                "status": .string("settled"),
                "debate_importance": .double(7.0),
            ],
            profile: .analysis
        )
        #expect(invalid.contains {
            $0.propertyKey == "type" && $0.code == .valueNotAllowed
        })
        #expect(!invalid.contains { $0.propertyKey == "status" })
        #expect(invalid.contains {
            $0.propertyKey == "debate_importance"
                && $0.code == .debateImportanceOutOfRange
        })
        #expect(invalid.contains {
            $0.propertyKey == "debate_importance_scope"
                && $0.code == .pairedPropertyMissing
        })

        let valid = PropertyContractCatalog.validate(
            frontmatter: [
                "type": .string("journal_article"),
                "status": .string("complete"),
                "debate_importance": .integer(7),
                "debate_importance_scope": .string("The fitting-attitude debate"),
            ],
            profile: .analysis
        )
        #expect(valid.isEmpty)

        let scopeWithoutRating = PropertyContractCatalog.validate(
            frontmatter: [
                "debate_importance_scope": .string("The fitting-attitude debate")
            ],
            profile: .analysis
        )
        #expect(scopeWithoutRating == [PropertyValidationIssue(
            propertyKey: "debate_importance",
            code: .pairedPropertyMissing,
            message: "debate_importance and debate_importance_scope must be provided together."
        )])
    }

    @Test("Research Unit validation reuses the Core declaration contract")
    func researchUnitValidation() {
        let issues = PropertyContractCatalog.validate(
            frontmatter: [
                "research_unit": .object([
                    "scope": .string(""),
                    "limitations": .array([.string("Outside the selected chapters")]),
                ])
            ],
            profile: .analysis
        )
        #expect(issues == [PropertyValidationIssue(
            propertyKey: "research_unit",
            code: .invalidResearchUnit,
            message: "Unsupported field: scope."
        )])
    }

    @Test("Malformed frontmatter remains exact and receives only an envelope issue")
    func malformedFrontmatterIsReadOnly() {
        let source = "---\r\ntitle: \"Unclosed\r\ncustom: keep\r\n---\r\n# Body\r\n"
        let document = NoteDocument(relativePath: "Analyses/Broken.md", rawContent: source)
        let originalBytes = document.sourceBytes
        let originalFingerprint = document.fingerprint

        let issues = PropertyContractCatalog.validate(
            document,
            profile: .analysis,
            context: .creation
        )

        #expect(issues.count == 1)
        #expect(issues.first?.code == .malformedFrontmatter)
        #expect(issues.first?.propertyKey == nil)
        #expect(document.rawContent == source)
        #expect(document.sourceBytes == originalBytes)
        #expect(document.fingerprint == originalFingerprint)
        #expect(throws: VaultRepositoryError.self) {
            try document.applying(
                .frontmatter(["title": .string("Replacement")]),
                timestampKey: nil
            )
        }
    }

    @Test("Contract profiles and key lookups remain immutable cached data")
    func catalogHasCachedStorageAndLookups() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumContracts/PropertyContract.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("private struct CachedProfile"))
        #expect(source.contains("let canonicalByKey: [String: PropertyContract]"))
        #expect(!source.contains("aliasByKey"))
        #expect(source.contains("private static let workProfile"))
        #expect(!source.contains("private static var workProfile"))
    }
}
