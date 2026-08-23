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
        let analysis = BuiltInNoteMetadataCatalog.contracts(for: .analysis).map(\.canonicalKey)
        #expect(analysis.count == 52)
        #expect(analysis.contains("publication_date"))
        #expect(analysis.contains("reviewed_authors"))
        #expect(analysis.contains("archive_location"))
        #expect(!analysis.contains("source_basis"))
        #expect(!analysis.contains("limitations"))
        #expect(!analysis.contains("summary"))
        #expect(BuiltInNoteMetadataCatalog.contracts(for: .topicMarkdown).map(\.canonicalKey) == [
            "aliases",
        ])
        #expect(BuiltInNoteMetadataCatalog.contracts(for: .draftProject).map(\.canonicalKey) == [
            "work_type", "coauthors",
        ])
    }

    @Test("Resolved custom Metadata is role-scoped and optional")
    func resolvedCustomCatalog() {
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .paperAnalysis: [
                MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
            ],
            .topicKnowledge: [
                MetadataFieldDefinition(key: "open_questions", valueKind: .textList),
            ],
            .output: [
                MetadataFieldDefinition(key: "word_budget", valueKind: .number),
            ],
        ])

        #expect(catalog.contract(for: "argument_stage", profile: .analysis)?.valueKind == .text)
        #expect(catalog.contract(for: "argument_stage", profile: .topicMarkdown) == nil)
        #expect(catalog.validate(fields: [:], profile: .analysis).isEmpty)
        #expect(catalog.validate(
            fields: ["argument_stage": .string("reconstruction")],
            profile: .analysis
        ).isEmpty)
        #expect(catalog.validate(
            fields: ["argument_stage": .string("wrong role")],
            profile: .topicMarkdown
        ).map(\.propertyKey) == ["argument_stage"])
        #expect(AnalysisSourceType.allCases.allSatisfy {
            catalog.isAnalysisFieldApplicable("argument_stage", sourceType: $0)
        })
    }

    @Test("Custom definitions cannot shadow authored YAML or built-in Metadata")
    func customDefinitionsRespectAuthorityBoundaries() {
        for key in ["summary", "keywords", "title"] {
            var settings = TriptychSettings()
            settings.metadataFields[.paperAnalysis] = [
                MetadataFieldDefinition(key: key, valueKind: .text),
            ]
            #expect(throws: TriptychSettingsValidationError.self) {
                try TriptychSettingsValidator.validate(settings)
            }
        }
    }

    @Test("Custom definitions are append-only after they become workspace authority")
    func customDefinitionsAreAppendOnly() throws {
        var current = TriptychSettings()
        current.metadataFields[.output] = [
            MetadataFieldDefinition(key: "draft_stage", valueKind: .text),
        ]
        var appended = current
        appended.metadataFields[.output, default: []].append(
            MetadataFieldDefinition(key: "target_words", valueKind: .number)
        )
        try TriptychSettingsValidator.validateTransition(from: current, to: appended)

        var renamed = current
        renamed.metadataFields[.output] = [
            MetadataFieldDefinition(key: "writing_stage", valueKind: .text),
        ]
        #expect(throws: TriptychSettingsValidationError.self) {
            try TriptychSettingsValidator.validateTransition(from: current, to: renamed)
        }
    }

    @Test("CreatorList accepts canonical person and literal entries")
    func creatorListShape() {
        let valid: [String: YAMLValue] = [
            "authors": .array([
                .object(["family": .string("Tappolet"), "given": .string("Christine")]),
                .object(["literal": .string("World Health Organization")]),
            ]),
        ]

        #expect(NoteMetadataCatalog.builtIn.validate(fields: valid, profile: .analysis).isEmpty)
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
            let issues = NoteMetadataCatalog.builtIn.validate(
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
        #expect(NoteMetadataCatalog.builtIn.validate(
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
            #expect(NoteMetadataCatalog.builtIn.validate(
                fields: ["publication_date": .string(value)],
                profile: .analysis
            ).isEmpty)
        }
        #expect(NoteMetadataCatalog.builtIn.validate(
            fields: ["publication_date": .integer(2026)],
            profile: .analysis
        ).map(\.code) == [.invalidValueKind])
    }

    @Test("Source types have one CSL mapping and valid profile partitions")
    func sourceTypeProfiles() {
        let canonical = Set(NoteMetadataCatalog.builtIn.analysisCanonicalKeys)
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
