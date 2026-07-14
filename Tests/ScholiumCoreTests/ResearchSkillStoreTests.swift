import Foundation
import Testing
@testable import ScholiumCore

@Suite("Triptych-local Research Guidance skills")
struct ResearchSkillStoreTests {
    @Test("Discovery is confined to direct SKILL.md packages under the portable root")
    func boundedDiscovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.create(id: "local-method", source: Self.validSource(name: "Local Method"))

        let nested = fixture.control
            .appendingPathComponent("skills/nested/deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.validSource(name: "Nested").write(
            to: nested.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        try Self.validSource(name: "Research Note").write(
            to: fixture.root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )

        let skills = try await store.skills()

        #expect(skills.contains { $0.id == "local-method" && $0.origin == .triptych })
        #expect(!skills.contains { $0.name == "Nested" || $0.name == "Research Note" })
        #expect(skills.filter { $0.origin == .bundled }.count == 2)
    }

    @Test("Malformed local skills remain visible and are excluded from instruction assembly")
    func malformedSkillIsVisibleButUnavailable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.create(id: "broken-skill", source: "---\nname: Broken\n---\n")

        let skills = try await store.skills()
        let broken = try #require(skills.first { $0.id == "broken-skill" })
        let assembly = try await store.instructionAssembly()

        #expect(!broken.isValid)
        #expect(broken.validationIssues.contains { $0.contains("description") })
        #expect(!assembly.contains("broken-skill"))
        #expect(assembly.contains("scholium-source-fidelity"))
    }

    @Test("Non-UTF-8 skill source remains visible as a recoverable structural error")
    func nonUTF8SkillIsVisible() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = fixture.control.appendingPathComponent("skills/binary-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00]).write(to: package.appendingPathComponent("SKILL.md"))
        let store = ResearchSkillStore(controlURL: fixture.control)

        let skill = try #require(try await store.skills().first { $0.id == "binary-skill" })

        #expect(!skill.isValid)
        #expect(skill.validationIssues.contains { $0.contains("UTF-8") })
        #expect(skill.revision == nil)
    }

    @Test("Writes reject traversal identifiers and stale package revisions")
    func traversalAndStaleWriteRejection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.create(id: "../escape", source: Self.validSource(name: "Escape"))
        }
        let created = try await store.create(id: "safe-skill", source: Self.validSource(name: "Safe"))
        let revision = try #require(created.revision)
        let sourceURL = fixture.control.appendingPathComponent("skills/safe-skill/SKILL.md")
        try Self.validSource(name: "External Change").write(to: sourceURL, atomically: true, encoding: .utf8)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.save(
                id: "safe-skill",
                source: Self.validSource(name: "Stale Save"),
                expectedRevision: revision
            )
        }
    }

    @Test("Symlink roots fail closed and symlink packages are never discovered")
    func symlinkRejection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = fixture.root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let skillsURL = fixture.control.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture.control, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: skillsURL, withDestinationURL: external)
        let unsafeStore = ResearchSkillStore(controlURL: fixture.control)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await unsafeStore.prepareSkillsFolder()
        }

        try FileManager.default.removeItem(at: skillsURL)
        try FileManager.default.createDirectory(at: skillsURL, withIntermediateDirectories: true)
        let realPackage = external.appendingPathComponent("linked-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: realPackage, withIntermediateDirectories: true)
        try Self.validSource(name: "Linked").write(
            to: realPackage.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: skillsURL.appendingPathComponent("linked-skill"),
            withDestinationURL: realPackage
        )
        let safeStore = ResearchSkillStore(controlURL: fixture.control)
        let skills = try await safeStore.skills()

        #expect(!skills.contains { $0.id == "linked-skill" })
    }

    @Test("Bundled customization, rename, save, deletion, and reset preserve package identity")
    func managementLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        let customized = try await store.duplicateBundled(
            id: "scholium-source-fidelity",
            as: "scholium-source-fidelity"
        )
        #expect(customized.origin == .customizedBundled)
        let customizedRevision = try #require(customized.revision)
        try await store.resetBundledCustomization(
            id: customized.id,
            expectedRevision: customizedRevision
        )
        #expect(try await store.skills().first { $0.id == customized.id }?.origin == .bundled)

        let created = try await store.create(id: "draft-method", source: Self.validSource(name: "Draft"))
        let renamed = try await store.rename(
            id: created.id,
            to: "final-method",
            expectedRevision: try #require(created.revision)
        )
        let saved = try await store.save(
            id: renamed.id,
            source: Self.validSource(name: "Final"),
            expectedRevision: try #require(renamed.revision)
        )
        #expect(saved.name == "Final")
        try await store.delete(id: saved.id, expectedRevision: try #require(saved.revision))
        #expect(!(try await store.skills()).contains { $0.id == saved.id })
    }

    private static func validSource(name: String) -> String {
        """
        ---
        name: \(name)
        description: Reusable guidance for a bounded research task.
        ---
        Inspect the relevant sources and preserve explicit uncertainty.
        """
    }

    private struct Fixture {
        let root: URL
        let control: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScholiumResearchSkills-\(UUID().uuidString)", isDirectory: true)
            control = root.appendingPathComponent(".scholium", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
