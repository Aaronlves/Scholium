import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Workflow schema profiles")
struct WorkflowSchemaTests {
    @Test("Registered vault role overrides folder spelling")
    func registeredRoleWins() {
        #expect(
            WorkflowProfileResolver.resolve(
                vaultRole: .sourceCorpus
            ) == .analysis)
        #expect(
            WorkflowProfileResolver.resolve(
                vaultRole: .topicKnowledge
            ) == .topicMarkdown)
    }

    @Test("Unregistered files remain generic regardless of old metadata or folders")
    func unregisteredFilesRemainGeneric() {
        #expect(
            WorkflowProfileResolver.resolve(
                vaultRole: .other
            ) == .genericMarkdown)
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
