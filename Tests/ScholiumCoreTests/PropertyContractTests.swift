import Foundation
import ScholiumContracts
import Testing

@Suite("Authored YAML and managed metadata contracts")
struct PropertyContractTests {
    @Test("Authored YAML has exactly summary and keywords semantics")
    func analysisCatalog() throws {
        let contracts = PropertyContractCatalog.contracts(for: .analysis)
        let keys = contracts.map(\.canonicalKey)

        #expect(keys == ["summary", "keywords"])
        #expect(PropertyContractCatalog.contracts(for: .topicMarkdown).map(\.canonicalKey)
            == keys)
        #expect(PropertyContractCatalog.contracts(for: .draftProject).map(\.canonicalKey)
            == keys)
    }

    @Test("Managed metadata retains role-specific structured vocabularies")
    func roleCatalogs() {
        let analysis = NoteMetadataContractCatalog.contracts(for: .analysis).map(\.canonicalKey)
        #expect(analysis.count == 52)
        #expect(analysis.contains("publication_date"))
        #expect(analysis.contains("reviewed_authors"))
        #expect(analysis.contains("archive_location"))
        #expect(!analysis.contains("source_basis"))
        #expect(!analysis.contains("limitations"))
        #expect(!analysis.contains("summary"))
        #expect(NoteMetadataContractCatalog.contracts(for: .topicMarkdown).map(\.canonicalKey) == [
            "aliases",
        ])
        #expect(NoteMetadataContractCatalog.contracts(for: .draftProject).map(\.canonicalKey) == [
            "work_type", "coauthors",
        ])
    }

    @Test("CreatorList accepts canonical person and literal entries")
    func creatorListShape() {
        let valid: [String: YAMLValue] = [
            "authors": .array([
                .object(["family": .string("Tappolet"), "given": .string("Christine")]),
                .object(["literal": .string("World Health Organization")]),
            ]),
        ]

        #expect(NoteMetadataContractCatalog.validate(fields: valid, profile: .analysis).isEmpty)
    }

    @Test("CreatorList rejects mixed, unknown, empty, and legacy string shapes")
    func creatorListRefusals() {
        let invalidValues: [YAMLValue] = [
            .array([.string("Christine Tappolet")]),
            .array([.object(["given": .string("Christine")])]),
            .array([.object(["literal": .string("WHO"), "family": .string("WHO")])]),
            .array([.object(["family": .string("Tappolet"), "orcid": .string("x")])]),
            .array([.object(["family": .integer(123)])]),
            .array([]),
        ]

        for value in invalidValues {
            let issues = NoteMetadataContractCatalog.validate(
                fields: ["authors": value],
                profile: .analysis
            )
            #expect(issues.map(\.code) == [.invalidCreator])
        }
    }

    @Test("Text lists and tags reject scalar coercion")
    func textCollectionsRequireStrings() {
        #expect(PropertyContractCatalog.validate(
            frontmatter: ["keywords": .array([.boolean(true), .integer(1)])],
            profile: .analysis
        ).map(\.code) == [.invalidValueKind])
        #expect(NoteMetadataContractCatalog.validate(
            fields: ["aliases": .array([.boolean(true), .integer(1)])],
            profile: .topicMarkdown
        ).map(\.code) == [.invalidValueKind])
    }

    @Test("Structured editing accepts repairable empty shapes but rejects shape guessing")
    func targetedStructuredEditingShapes() {
        #expect(PropertyContractCatalog.supportsTargetedStructuredEditing(
            .string(""),
            as: .date
        ))
        #expect(PropertyContractCatalog.supportsTargetedStructuredEditing(
            .array([]),
            as: .textList
        ))
        #expect(PropertyContractCatalog.supportsTargetedStructuredEditing(
            .array([.object(["family": .string("")])]),
            as: .creatorList
        ))
        #expect(!PropertyContractCatalog.supportsTargetedStructuredEditing(
            .array([.string("Legacy Author")]),
            as: .creatorList
        ))
        #expect(!PropertyContractCatalog.supportsTargetedStructuredEditing(
            .object(["nested": .string("exact")]),
            as: .text
        ))
    }

    @Test("Dates remain source-safe strings and are not parsed or normalized")
    func dateShape() {
        for value in ["2026", "circa 1920", "forthcoming?", "1990/1992"] {
            #expect(NoteMetadataContractCatalog.validate(
                fields: ["publication_date": .string(value)],
                profile: .analysis
            ).isEmpty)
        }
        #expect(NoteMetadataContractCatalog.validate(
            fields: ["publication_date": .integer(2026)],
            profile: .analysis
        ).map(\.code) == [.invalidValueKind])
    }

    @Test("Source types have one CSL mapping and valid profile partitions")
    func sourceTypeProfiles() {
        let canonical = Set(NoteMetadataContractCatalog.analysisCanonicalKeys)
        #expect(AnalysisSourceType.allCases.count == 18)
        #expect(Set(AnalysisSourceType.allCases.map(\.cslType)).contains("article-journal"))

        for sourceType in AnalysisSourceType.allCases {
            let profile = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
            let applicable = Set(profile.applicableFields)
            #expect(applicable.isSubset(of: canonical))
            #expect(Set(profile.recommendedFieldOrder).isSubset(of: applicable))
            #expect(Set(profile.serializationFieldOrder) == applicable)
            #expect(profile.serializationFieldOrder.first == "type")
        }
    }

    @Test("Retired and unknown keys remain undiagnosed custom source")
    func customSourceRemainsOutsideCanonicalValidation() {
        let issues = PropertyContractCatalog.validate(
            frontmatter: [
                "year": .integer(2020),
                "research_unit": .object(["completion": .string("complete")]),
                "zotero_item_key": .string("ABCD1234"),
                "title": .string("Retired YAML title"),
                "source_basis": .array([.string("Researcher decides")]),
                "limitations": .array([.string("Researcher decides")]),
                "custom_field": .object(["nested": .boolean(true)]),
            ],
            profile: .analysis
        )
        #expect(issues.isEmpty)
    }

    @Test("Typed authored YAML accepts only optional Summary and Keywords values")
    func authoredYAMLValuesAreBounded() throws {
        let values = try AuthoredNoteYAML(
            summary: "A navigation summary",
            keywords: ["fittingness", "value"]
        )
        let decoded = try JSONDecoder().decode(
            AuthoredNoteYAML.self,
            from: JSONEncoder().encode(values)
        )
        #expect(decoded == values)
        #expect(throws: DocumentCreationError.invalidAuthoredYAML) {
            try AuthoredNoteYAML(summary: "", keywords: [])
        }
        #expect(throws: DocumentCreationError.invalidAuthoredYAML) {
            try AuthoredNoteYAML(keywords: ["value", "value"])
        }
        #expect(throws: DocumentCreationError.invalidAuthoredYAML) {
            try JSONDecoder().decode(
                AuthoredNoteYAML.self,
                from: Data(#"{"summary":"ok","custom":true}"#.utf8)
            )
        }
    }
}
