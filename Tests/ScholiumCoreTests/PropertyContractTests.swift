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
            "title", "authors", "year", "type", "tags", "research_unit",
            "access", "text_reliability", "locators", "status",
            "debate_importance", "debate_importance_scope",
        ])
        #expect(topic.map(\.canonicalKey) == [
            "title", "aliases", "tags", "research_unit", "status",
        ])
        #expect(work.map(\.canonicalKey) == [
            "title", "authors", "kind", "tags", "research_unit", "status",
            "venue", "deadline",
        ])

        let researchUnit = try #require(
            PropertyContractCatalog.contract(for: "research_unit", profile: .analysis)
        )
        #expect(researchUnit.valueKind == .mapping)
        #expect(researchUnit.creationRequirement == .optional)
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
        #expect(PropertyContractCatalog.contract(
            for: "research_unit",
            profile: .paperAnalysisV1
        )?.creationRequirement == .optional)
    }

    @Test("Legacy aliases resolve to one canonical contract with canonical precedence")
    func aliasesAndCanonicalPrecedence() {
        #expect(PropertyContractCatalog.canonicalKey(
            for: "source_kind",
            profile: .analysis
        ) == "type")
        #expect(PropertyContractCatalog.canonicalKey(
            for: "analysis_status",
            profile: .analysis
        ) == "status")
        #expect(PropertyContractCatalog.canonicalKey(
            for: "analysis_status",
            profile: .topicMarkdown
        ) == "status")

        let canonicalWins = PropertyContractCatalog.validate(
            frontmatter: [
                "status": .string("reviewed"),
                "analysis_status": .string("not-current"),
            ],
            profile: .analysis
        )
        #expect(!canonicalWins.contains { $0.propertyKey == "status" })

        let legacyValueIsValidated = PropertyContractCatalog.validate(
            frontmatter: ["analysis_status": .string("not-current")],
            profile: .analysis
        )
        #expect(legacyValueIsValidated.contains {
            $0.propertyKey == "status" && $0.code == .valueNotAllowed
        })
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
                for alias in contract.legacyAliases {
                    #expect(PropertyContractCatalog.canonicalKey(
                        for: alias,
                        profile: profile
                    ) == contract.canonicalKey)
                }
            }
        }
    }

    @Test("Creation requirements do not invalidate existing legacy notes")
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
        #expect(invalid.contains {
            $0.propertyKey == "status" && $0.code == .valueNotAllowed
        })
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
            message: "Scope is required and cannot be empty."
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

    @Test("Dissertation v4 contracts derive controlled values and conditional creation fields")
    func dissertationV4Contracts() throws {
        let status = try #require(PropertyContractCatalog.contract(
            for: "status",
            profile: .dissertationControlV4
        ))
        #expect(status.allowedValues == DissertationControlV4.statuses.sorted())
        #expect(PropertyContractCatalog.contract(
            for: "schema_version",
            profile: .dissertationControlV4
        )?.creationRequirement == .required)
        #expect(PropertyContractCatalog.contract(
            for: "claim_kind",
            profile: .dissertationControlV4
        )?.constraints.contains(
            .requiredWhen(canonicalKey: "note_type", equals: "claim")
        ) == true)

        var frontmatter = Dictionary(
            uniqueKeysWithValues: PropertyContractCatalog.contracts(
                for: .dissertationControlV4
            ).compactMap { contract -> (String, YAMLValue)? in
                guard contract.creationRequirement == .required else { return nil }
                let value: YAMLValue = switch contract.valueKind {
                case .text, .multilineText, .date:
                    .string("value")
                case .choice:
                    .string(contract.allowedValues?.first ?? "value")
                case .number:
                    .integer(1)
                case .boolean:
                    .boolean(true)
                case .tags, .textList:
                    .array([.string(contract.allowedValues?.first ?? "value")])
                case .mapping:
                    .object(["value": .string("value")])
                }
                return (contract.canonicalKey, value)
            }
        )
        frontmatter["note_type"] = .string("claim")
        let issues = PropertyContractCatalog.validate(
            frontmatter: frontmatter,
            profile: .dissertationControlV4,
            context: .creation
        )
        #expect(issues.contains {
            $0.propertyKey == "claim_kind" && $0.code == .missingRequiredProperty
        })
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
        #expect(source.contains("let aliasByKey: [String: PropertyContract]"))
        #expect(source.contains("private static let dissertationV4Contracts"))
        #expect(!source.contains("private static var dissertationV4Contracts"))
    }
}
