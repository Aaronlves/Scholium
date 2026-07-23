import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workflow schema profiles")
struct WorkflowSchemaTests {
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

    @Test("Unregistered files remain generic regardless of old metadata or folders")
    func unregisteredFilesRemainGeneric() {
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .other,
            frontmatter: ["record_type": .string("paper_analysis")],
            relativePath: "papers/source.md"
        ) == .genericMarkdown)
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

    @Test("Default About fields exclude machine state and optional assessments")
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
        #expect(!analyses.visibleFields.contains("debate_importance"))
        #expect(!analyses.visibleFields.contains("debate_importance_scope"))
        #expect(analyses.editableFields.contains("debate_importance"))
        #expect(analyses.editableFields.contains("debate_importance_scope"))
        #expect(!works.visibleFields.contains("deadline"))
        #expect(!works.editableFields.contains("deadline"))
    }

    @Test("CLI role aliases do not become persisted registry spellings")
    func roleAliases() throws {
        #expect(VaultRole(commandLineValue: "sources") == .sourceCorpus)
        #expect(VaultRole(commandLineValue: "knowledge") == .topicKnowledge)
        #expect(VaultRole(commandLineValue: "project") == .draftProject)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(VaultRole.self, from: Data("\"sources\"".utf8))
        }
        #expect(
            try JSONDecoder().decode(
                VaultRole.self,
                from: Data("\"source_corpus\"".utf8)
            ) == .sourceCorpus
        )
    }
}
