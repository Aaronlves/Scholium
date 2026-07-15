import Foundation
import Testing
import ScholiumContracts
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
        let globalLikePackage = fixture.root.appendingPathComponent(
            ".codex/skills/global-method",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: globalLikePackage,
            withIntermediateDirectories: true
        )
        try Self.validSource(name: "Global Method").write(
            to: globalLikePackage.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let skills = try await store.skills()

        #expect(skills.contains { $0.id == "local-method" && $0.origin == .triptych })
        #expect(!skills.contains {
            $0.name == "Nested" || $0.name == "Research Note" || $0.name == "Global Method"
        })
        #expect(skills.filter { $0.origin == .bundled }.count >= 2)
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
        #expect(assembly.contains("scholium-core-protocol"))
        #expect(!assembly.contains("scholium-source-fidelity"))
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

    @Test("A symbolic-link Practice resource is visible as missing and cannot assemble")
    func symlinkPracticeResourceFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = fixture.control.appendingPathComponent(
            "skills/linked-practices",
            isDirectory: true
        )
        let references = package.appendingPathComponent("references", isDirectory: true)
        try FileManager.default.createDirectory(at: references, withIntermediateDirectories: true)
        let source = """
        ---
        name: Linked Practices
        description: Declares a linked Practice resource.
        scholium:
          role: practice
          supported_modes: [review]
          required_skills: [scholium-core-protocol]
          practice_resources:
            reviewer: references/Reviewer.md
        ---
        Apply only bounded regular resources.
        """
        try source.write(
            to: package.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        for name in ["FOUNDATIONAL-DIMENSIONS.md", "COMPOSITION-RULES.md"] {
            try "# \(name)\n".write(
                to: references.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        let outside = fixture.root.appendingPathComponent("Reviewer.md")
        try "# Linked reviewer\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: references.appendingPathComponent("Reviewer.md"),
            withDestinationURL: outside
        )
        let store = ResearchSkillStore(controlURL: fixture.control)
        let linked = try #require(try await store.skills().first {
            $0.id == "linked-practices"
        })

        #expect(!linked.isValid)
        #expect(linked.validationIssues.contains { $0.contains("Reviewer.md") })
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.resolvedPackages(
                for: .review,
                requestedSkillIDs: ["linked-practices"]
            )
        }
    }

    @Test("Official duplication copies the complete package under an independent identity")
    func managementLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        let duplicated = try await store.duplicateBundled(
            id: "scholium-source-analysis",
            as: "source-analysis-copy"
        )
        #expect(duplicated.origin == .triptych)
        #expect(duplicated.id == "source-analysis-copy")
        let duplicatedResources = try await store.resourcePaths(id: duplicated.id)
        #expect(duplicatedResources.contains("SKILL.md"))
        #expect(duplicatedResources.contains("references/method.md"))
        #expect(duplicatedResources.contains("references/report-templates.md"))
        #expect(try await store.resource(
            id: duplicated.id,
            relativePath: "references/method.md"
        ).contains("Three-pass"))
        let citation = try await store.duplicateBundled(
            id: "scholium-citation-verification",
            as: "apa-citation-method"
        )
        #expect(citation.origin == .triptych)
        #expect(try await store.resourcePaths(id: citation.id).contains(
            "references/apa-7-starter.md"
        ))
        let prose = try await store.duplicateBundled(
            id: "scholium-prose-control",
            as: "my-prose-control"
        )
        #expect(prose.origin == .triptych)
        #expect(try await store.resourcePaths(id: prose.id).contains(
            "references/academic-prose-style.md"
        ))
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.duplicateBundled(
                id: "scholium-core-protocol",
                as: "core-copy"
            )
        }

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

    @Test("Package revisions include local references and resource paths reject traversal")
    func localPackageResourcesAndRevision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let created = try await store.create(
            id: "practice-library",
            source: Self.validSource(name: "Practice Library")
        )
        let packageURL = fixture.control.appendingPathComponent(
            "skills/practice-library",
            isDirectory: true
        )
        let references = packageURL.appendingPathComponent("references", isDirectory: true)
        try FileManager.default.createDirectory(at: references, withIntermediateDirectories: false)
        try "# Reviewer\n\nApply exact review criteria.\n".write(
            to: references.appendingPathComponent("Reviewer.md"),
            atomically: true,
            encoding: .utf8
        )

        let reloaded = try await store.package(id: created.id)
        #expect(reloaded.revision != created.revision)
        #expect(try await store.resourcePaths(id: created.id) == [
            "SKILL.md",
            "references/Reviewer.md",
        ])
        #expect(try await store.resource(
            id: created.id,
            relativePath: "references/Reviewer.md"
        ).contains("exact review criteria"))
        await #expect(throws: ResearchSkillCatalogError.self) {
            _ = try await store.resource(id: created.id, relativePath: "../outside.md")
        }
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.save(
                id: created.id,
                source: Self.validSource(name: "Stale Practice Library"),
                expectedRevision: try #require(created.revision)
            )
        }
    }

    @Test("Legacy embedded micro-skills are no longer part of the bundled catalog")
    func noLegacyEmbeddedMicroSkills() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let skills = try await ResearchSkillStore(controlURL: fixture.control).skills()
        #expect(!skills.contains { $0.id == "scholium-source-fidelity" })
        #expect(!skills.contains { $0.id == "scholium-triptych-editing" })
    }

    @Test("Protected identifier collisions remain visible but never shadow official packages")
    func protectedCollisionIsVisibleAndBlocked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let package = fixture.control.appendingPathComponent(
            "skills/scholium-core-protocol",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Self.validSource(name: "Conflicting Core").write(
            to: package.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = ResearchSkillStore(controlURL: fixture.control)

        let collisions = try await store.skills().filter { $0.id == "scholium-core-protocol" }

        #expect(collisions.count == 2)
        #expect(collisions.contains { $0.origin == .bundled && $0.isValid })
        #expect(collisions.contains {
            $0.origin == .triptych
                && !$0.isValid
                && $0.revision != nil
                && $0.validationIssues.contains { $0.contains("protected Scholium package") }
        })
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.instructionAssembly(mode: .dialogue)
        }
    }

    @Test("Legacy local packages remain explicit-only specialists supporting ordinary modes")
    func legacyRoutingDefaults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let package = try await store.create(
            id: "legacy-method",
            source: Self.validSource(name: "Legacy Method")
        )

        #expect(package.role == "specialist")
        #expect(package.skillClass == .researcher)
        #expect(package.supportedModes == [.all])
        #expect(package.requiredSkillIDs.isEmpty)
        #expect(package.automaticModes.isEmpty)
        let defaultAssembly = try await store.instructionAssembly(mode: .analyze)
        #expect(!defaultAssembly.contains("legacy-method"))
        let explicit = try await store.instructionAssembly(
            mode: .analyze,
            requestedSkillIDs: ["legacy-method"]
        )
        #expect(explicit.contains("legacy-method"))
    }

    @Test("Namespaced local routing participates in one protected and local dependency graph")
    func namespacedRoutingAndCombinedDependencies() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.create(
            id: "local-method",
            source: Self.routedSource(
                name: "Local Method",
                role: "specialist",
                modes: ["analyze"],
                dependencies: ["scholium-core-protocol"]
            )
        )
        let workflow = try await store.create(
            id: "local-workflow",
            source: Self.routedSource(
                name: "Local Workflow",
                role: "workflow",
                modes: ["analyze"],
                dependencies: ["local-method"]
            )
        )

        #expect(workflow.role == "workflow")
        #expect(workflow.supportedModes == [.analyze])
        #expect(workflow.requiredSkillIDs == ["local-method"])
        let resolved = try await store.resolvedPackages(
            for: .analyze,
            requestedSkillIDs: ["local-workflow"]
        )
        #expect(resolved.map(\.id) == [
            "scholium-core-protocol",
            "local-method",
            "local-workflow",
        ])
    }

    @Test("Routing spoofing and unknown keys remain visible but ineligible")
    func spoofingAndUnknownRoutingKeys() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let source = """
        ---
        name: Spoof Attempt
        description: Attempts to acquire protected behavior.
        class: system
        update_policy: release-managed-protected
        scholium:
          role: workflow
          supported_modes: [analyze]
          automatic_modes: [all]
          class: system
        ---
        Remain researcher-owned and explicit-only.
        """
        _ = try await store.create(id: "spoof-attempt", source: source)
        let package = try #require(try await store.skills().first {
            $0.id == "spoof-attempt"
        })

        #expect(package.skillClass == .researcher)
        #expect(package.updatePolicy == "researcher-owned")
        #expect(package.automaticModes.isEmpty)
        #expect(!package.isValid)
        #expect(package.validationIssues.contains { $0.contains("automatic_modes") })
        #expect(package.validationIssues.contains { $0.contains("class") })
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.resolvedPackages(
                for: .analyze,
                requestedSkillIDs: ["spoof-attempt"]
            )
        }
    }

    @Test("Dependency cycles and missing Practice resources fail closed")
    func cyclesAndMissingPracticeResources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let skills = fixture.control.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try Self.writePackage(
            id: "cycle-a",
            source: Self.routedSource(
                name: "Cycle A",
                role: "specialist",
                modes: ["review"],
                dependencies: ["cycle-b"]
            ),
            skillsURL: skills
        )
        try Self.writePackage(
            id: "cycle-b",
            source: Self.routedSource(
                name: "Cycle B",
                role: "specialist",
                modes: ["review"],
                dependencies: ["cycle-a"]
            ),
            skillsURL: skills
        )
        let practiceSource = """
        ---
        name: Incomplete Practices
        description: Declares a Practice without its bounded references.
        scholium:
          role: practice
          supported_modes: [review]
          required_skills: [scholium-core-protocol]
          practice_resources:
            reviewer: references/Reviewer.md
        ---
        Apply only explicitly selected Practices.
        """
        try Self.writePackage(
            id: "incomplete-practices",
            source: practiceSource,
            skillsURL: skills
        )
        let store = ResearchSkillStore(controlURL: fixture.control)
        let packages = try await store.skills()
        let cycleA = try #require(packages.first { $0.id == "cycle-a" })
        let practices = try #require(packages.first { $0.id == "incomplete-practices" })

        #expect(!cycleA.isValid)
        #expect(cycleA.validationIssues.contains { $0.contains("cycle") })
        #expect(!practices.isValid)
        #expect(practices.validationIssues.contains {
            $0.contains("FOUNDATIONAL-DIMENSIONS")
        })
        #expect(practices.validationIssues.contains { $0.contains("Reviewer.md") })
        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.resolvedPackages(
                for: .review,
                requestedSkillIDs: ["incomplete-practices"]
            )
        }
    }

    @Test("Duplicated bundled packages retain routing metadata and every declared resource")
    func duplicatedRoutingMetadataIsComplete() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let copy = try await store.duplicateBundled(
            id: "scholium-philosophical-practices",
            as: "my-philosophical-practices"
        )
        let source = try await store.resource(id: copy.id, relativePath: "SKILL.md")
        let paths = try await store.resourcePaths(id: copy.id)

        #expect(copy.origin == .triptych)
        #expect(copy.role == "practice")
        #expect(copy.supportedModes.contains(.review))
        #expect(copy.requiredSkillIDs == ["scholium-core-protocol"])
        #expect(copy.practiceResources["reviewer"] == "references/Reviewer.md")
        #expect(source.contains("scholium:"))
        #expect(source.contains("practice_resources:"))
        #expect(paths.contains("references/FOUNDATIONAL-DIMENSIONS.md"))
        #expect(paths.contains("references/COMPOSITION-RULES.md"))
        #expect(paths.contains("references/Reviewer.md"))
        #expect(copy.isValid)
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

    private static func routedSource(
        name: String,
        role: String,
        modes: [String],
        dependencies: [String]
    ) -> String {
        """
        ---
        name: \(name)
        description: Reusable guidance with explicit Scholium routing metadata.
        scholium:
          role: \(role)
          supported_modes: [\(modes.joined(separator: ", "))]
          required_skills: [\(dependencies.joined(separator: ", "))]
        ---
        Preserve source fidelity, task scope, and researcher authority.
        """
    }

    private static func writePackage(
        id: String,
        source: String,
        skillsURL: URL
    ) throws {
        let package = skillsURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try source.write(
            to: package.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
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
