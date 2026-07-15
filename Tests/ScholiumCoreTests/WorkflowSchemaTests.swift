import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workflow schema profiles")
struct WorkflowSchemaTests {
    @Test("Dissertation control v4 is distinguished without changing the vault role")
    func dissertationV4Profile() {
        let profile = WorkflowProfileResolver.resolve(
            vaultRole: .dissertationControl,
            frontmatter: ["schema_version": .string("dissertation-control-v4")],
            relativePath: "02 Claims/Project Claims/CLM-001.md"
        )
        #expect(profile == .dissertationControlV4)
    }
    @Test("Registered vault role overrides folder spelling")
    func registeredRoleWins() {
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .sourceCorpus,
            frontmatter: [:],
            relativePath: "Level 3 - Metaethics/fit.md"
        ) == .analysis)
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .topicKnowledge,
            frontmatter: ["note_type": .string("argument_dossier")],
            relativePath: "output/chapter.md"
        ) == .topicMarkdown)
    }

    @Test("Explicit schema metadata precedes legacy folder rules")
    func schemaMetadataWins() {
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .other,
            frontmatter: ["schema_version": .string("dissertation-control-v3")],
            relativePath: "papers/control.md"
        ) == .dissertationControlV3)
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .other,
            frontmatter: ["record_type": .string("paper_analysis")],
            relativePath: "misc/source.md"
        ) == .paperAnalysisV1)
    }

    @Test("Nested paper audit remains a structured, filterable read model")
    func nestedAuditProjection() {
        let source = """
        ---
        record_type: paper_analysis
        schema_version: paper-analysis-yaml-v1
        audit:
          status: pass
          last_checked_at: '2026-07-09T15:06:30+08:00'
          checks:
            structure_complete: true
            human_reviewed: true
          notes: Headings and frontmatter complete.
        ---
        # Analysis
        """
        let document = NoteDocument(relativePath: "Level 3/source.md", rawContent: source)

        guard case .object(let audit) = document.parsedFrontmatter["audit"] else {
            Issue.record("Expected nested audit mapping")
            return
        }
        let flattened = YAMLValue.object(audit).flattenedScalarValues
        #expect(flattened["status"] == "pass")
        #expect(flattened["checks.structure_complete"] == "true")
        #expect(flattened["checks.human_reviewed"] == "true")
        #expect(flattened["notes"] == "Headings and frontmatter complete.")
    }

    @Test("Triptych properties prefer canonical keys and read legacy aliases")
    func triptychAliases() {
        let legacy: [String: YAMLValue] = [
            "source_kind": .string("article"),
            "analysis_status": .string("complete"),
            "relevance_rating": .integer(8),
        ]
        #expect(TriptychProperty.value(for: "type", in: legacy) == .string("article"))
        #expect(TriptychProperty.value(for: "status", in: legacy) == .string("complete"))
        #expect(TriptychProperty.value(for: "relevance", in: legacy) == .integer(8))
        #expect(TriptychProperty.legacyKey(for: "status", in: legacy) == "analysis_status")

        let mixed = legacy.merging(["status": .string("reviewed")]) { _, canonical in canonical }
        #expect(TriptychProperty.value(for: "status", in: mixed) == .string("reviewed"))
    }

    @Test("Save profiles do not inject frontmatter timestamps")
    func triptychTimestampsAreAppOwned() {
        #expect(SchemaProfileID.analysis.automaticSaveTimestampKey(in: [:]) == nil)
        #expect(SchemaProfileID.paperAnalysisV1.automaticSaveTimestampKey(in: [:]) == nil)
        #expect(SchemaProfileID.paperAnalysisV1.automaticSaveTimestampKey(
            in: ["analysis_updated_at": .string("2025-01-01")]
        ) == nil)
        #expect(SchemaProfileID.draftProject.automaticSaveTimestampKey(
            in: ["modified": .string("2025-01-01")]
        ) == nil)
    }

    @Test("Default Properties exclude agent-owned time and contextual relevance")
    func defaultPropertyVocabulary() throws {
        let analyses = try #require(TriptychSettings.defaultProperties[.paperAnalysis])
        let topics = try #require(TriptychSettings.defaultProperties[.topicKnowledge])
        let works = try #require(TriptychSettings.defaultProperties[.output])

        for configuration in [analyses, topics, works] {
            #expect(!configuration.visibleFields.contains("last_modified_by"))
            #expect(!configuration.visibleFields.contains("last_modified_at"))
            #expect(!configuration.editableFields.contains("last_modified_by"))
            #expect(!configuration.editableFields.contains("last_modified_at"))
        }
        #expect(!analyses.visibleFields.contains("relevance"))
        #expect(!analyses.editableFields.contains("relevance"))
        #expect(analyses.visibleFields.contains("debate_importance"))
        #expect(analyses.visibleFields.contains("debate_importance_scope"))
    }

    @Test("Legacy CLI role spellings decode into precise roles")
    func legacyRoleMigration() throws {
        #expect(VaultRole(commandLineValue: "sources") == .sourceCorpus)
        #expect(VaultRole(commandLineValue: "knowledge") == .topicKnowledge)
        #expect(VaultRole(commandLineValue: "project") == .draftProject)
        #expect(try JSONDecoder().decode(VaultRole.self, from: Data("\"sources\"".utf8)) == .sourceCorpus)
    }
}
