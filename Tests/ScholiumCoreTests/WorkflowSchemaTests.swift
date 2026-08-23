import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workflow schema profiles")
struct WorkflowSchemaTests {
    @Test("Registered vault role overrides folder spelling")
    func registeredRoleWins() {
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .sourceCorpus
        ) == .analysis)
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .topicKnowledge
        ) == .topicMarkdown)
    }

    @Test("Unregistered files remain generic regardless of old metadata or folders")
    func unregisteredFilesRemainGeneric() {
        #expect(WorkflowProfileResolver.resolve(
            vaultRole: .other
        ) == .genericMarkdown)
    }

    @Test("Default optional machine fields exclude authored YAML and machine state")
    func defaultPropertyVocabulary() throws {
        let analyses = try #require(TriptychSettings.defaultAbout[.paperAnalysis])
        let topics = try #require(TriptychSettings.defaultAbout[.topicKnowledge])
        let works = try #require(TriptychSettings.defaultAbout[.output])

        for configuration in [analyses, topics, works] {
            #expect(!configuration.visibleFields.contains("summary"))
            #expect(!configuration.visibleFields.contains("keywords"))
            #expect(!configuration.visibleFields.contains("last_modified_by"))
            #expect(!configuration.visibleFields.contains("last_modified_at"))
        }
        #expect(!analyses.visibleFields.contains("relevance"))
        #expect(!analyses.visibleFields.contains("debate_importance"))
        #expect(!analyses.visibleFields.contains("debate_importance_scope"))
        #expect(!works.visibleFields.contains("deadline"))
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
