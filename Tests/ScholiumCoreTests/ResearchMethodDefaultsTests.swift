import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Bundled current Research Method resources")
struct ResearchMethodDefaultsTests {
    @Test("Every Platform Action has one exact bundled primary Method")
    func bundledMethodsMatchPlatformActions() throws {
        let definitions = BundledResearchMethodDefaults.definitions
        #expect(Set(definitions.map(\.actionID)).count == definitions.count)
        #expect(Set(definitions.map(\.actionID)) == Set(
            PlatformActionCatalog.definitions.map(\.actionID)
        ))
        for definition in definitions {
            let source = try BundledResearchMethodDefaults.primarySource(
                for: definition.actionID
            )
            #expect(!source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(definition.resources.first == "SKILL.md")
            #expect(definition.resources.allSatisfy {
                !$0.hasPrefix("/") && !$0.contains("..")
            })
        }
    }

    @Test("Default bootstrap creates registrations and exact Practice documents")
    func bootstrapCreatesCurrentOwners() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-current-methods-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let triptychID = UUID()
        let store = ResearchConfigurationStore(
            controlURL: root,
            triptychID: triptychID
        )
        try await store.bootstrapDefaults()

        let registrations = try #require(await store.registrationSnapshot())
        #expect(registrations.document.registrations.count
            == PlatformActionCatalog.definitions.count)
        for registration in registrations.document.registrations
            where registration.isEnabled
        {
            let method = try await store.methodSnapshot(for: registration.actionID)
            #expect(method.registration.key == registration.key)
            #expect(!method.primaryMarkdownSource.isEmpty)
        }
        let practices = try await store.practiceCatalog()
        #expect(practices.count == 9)
        #expect(Set(practices.map(\.title)).contains("Dialectical Partner"))
    }

    @Test("The resource tree has no package catalog or workflow evaluation owner")
    func noPackageCatalogResource() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("catalog.yaml").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("evals", isDirectory: true).path
        ))
        for definition in BundledResearchMethodDefaults.definitions {
            let directory = root.appendingPathComponent(
                definition.resourceDirectory,
                isDirectory: true
            )
            for resource in definition.resources {
                #expect(FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(resource).path
                ))
            }
        }
    }

    @Test("System Agent references describe only the authenticated current transport")
    func currentAgentTransportReferences() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let core = repositoryRoot.appendingPathComponent(
            "ScholiumCore/Resources/Skills/Scholium System Skills/scholium-core-protocol/SKILL.md"
        )
        let transportURL = core.deletingLastPathComponent()
            .appendingPathComponent("references/agent-transport.md")
        let coreSource = try String(contentsOf: core, encoding: .utf8)
        let transport = try String(contentsOf: transportURL, encoding: .utf8)

        for requirement in [
            "Effective authority is",
            "Do not infer belief, intention, understanding",
            "Scholium finalizes one immutable Result partition",
            "Method and Practice prose may identify a scholarly need",
        ] {
            #expect(coreSource.contains(requirement))
        }
        for command in [
            "scholium agent pair --run <run-locator>",
            "scholium agent submit-result --run <run-locator> --from <result.json|->",
            "scholium agent resolve-write-conflict",
            "scholium agent end --run <run-locator>",
            "current bounded write-set view",
        ] {
            #expect(transport.contains(command))
        }
        #expect(transport.contains(
            "There is no current `scholium skills`, `scholium workflow`, or"
        ))
        for retiredInvocation in [
            "```sh\nscholium skills",
            "```sh\nscholium workflow",
            "```sh\nscholium action complete",
        ] {
            #expect(!transport.contains(retiredInvocation))
        }
    }
}
