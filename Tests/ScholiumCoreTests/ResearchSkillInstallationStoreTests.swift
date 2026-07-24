import Darwin
import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Staged Researcher Skill installation")
struct ResearchSkillInstallationStoreTests {
    @Test("Expired staging automatically frees private preparation capacity")
    func expiredPreparationCannotInstall() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let installer = ResearchSkillInstallationStore(
            hooks: .none,
            preparationLifetime: 1
        )
        var preparations: [ResearchSkillInstallationPreparation] = []
        for _ in 0..<16 {
            preparations.append(
                try await installer.stage(directoryURL: fixture.source)
            )
        }
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try await Task.sleep(for: .milliseconds(1_500))
        let replacement = try await installer.stage(directoryURL: fixture.source)
        #expect(replacement.packageID == fixture.packageID)
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()

        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.install(
                preparations[0],
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
        }
        await #expect(throws: ResearchSkillError.self) {
            _ = try await destination.package(id: fixture.packageID)
        }
    }

    @Test("Only a nonlinked local directory may enter staging")
    func acceptsOnlyLocalDirectories() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let installer = ResearchSkillInstallationStore()

        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(
                directoryURL: URL(string: "https://example.invalid/skill")!
            )
        }
        let archive = fixture.root.appendingPathComponent("skill.zip")
        try Data("not an archive route\n".utf8).write(to: archive)
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: archive)
        }
        let linkedDirectory = fixture.root.appendingPathComponent(
            "linked-researcher-skill",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory,
            withDestinationURL: fixture.source
        )
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: linkedDirectory)
        }
    }

    @Test("A reviewed directory installs as disabled independent Triptych snapshots")
    func installsIndependentDisabledSnapshots() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()

        let first = ResearchSkillStore(controlURL: fixture.firstControl)
        let second = ResearchSkillStore(controlURL: fixture.secondControl)
        let firstBinding = try await first.installDefaultWorkingMethods()
        let secondBinding = try await second.installDefaultWorkingMethods()
        let installer = ResearchSkillInstallationStore()

        let preparation = try await installer.stage(directoryURL: fixture.source)
        #expect(preparation.packageID == fixture.packageID)
        #expect(preparation.originDisplayName == fixture.packageID)
        #expect(preparation.files.map(\.relativePath) == [
            "SKILL.md",
            "evals/strong-objection.md",
            "references/evaluation-questions.md",
        ])
        #expect(preparation.purpose == "Pressure-test a philosophical claim with counterexamples.")
        #expect(preparation.applicableRoles == [.work])
        #expect(preparation.proposedActionIDs == [.critique])
        #expect(preparation.actionPlacement == .researcherSkills)
        #expect(preparation.permissionState == .actionProfileRequired)
        #expect(preparation.installsDisabled)
        let encodedPreparation = try JSONEncoder().encode(preparation)
        let preparationJSON = try #require(
            String(data: encodedPreparation, encoding: .utf8)
        )
        #expect(!preparationJSON.contains(fixture.root.path))
        #expect(!preparationJSON.contains("Reconstruct the claim charitably"))
        #expect(!preparationJSON.contains("# Evaluation questions"))

        let firstID = UUID()
        let secondID = UUID()
        let outcome = try await installer.install(
            preparation,
            destinations: [
                ResearchSkillInstallationDestination(
                    triptychID: firstID,
                    skillStore: first
                ),
                ResearchSkillInstallationDestination(
                    triptychID: secondID,
                    skillStore: second
                ),
            ]
        )
        #expect(outcome.installations.count == 2)
        #expect(outcome.installations.allSatisfy { !$0.isEnabled })
        #expect(try await first.package(id: fixture.packageID).revision
            == preparation.packageRevision)
        #expect(try await second.package(id: fixture.packageID).revision
            == preparation.packageRevision)
        #expect(try await first.workingMethodBindingSnapshot()?.revision
            == firstBinding.revision)
        #expect(try await second.workingMethodBindingSnapshot()?.revision
            == secondBinding.revision)

        let firstEntry = fixture.firstControl
            .appendingPathComponent("skills/\(fixture.packageID)/SKILL.md")
        let secondEntry = fixture.secondControl
            .appendingPathComponent("skills/\(fixture.packageID)/SKILL.md")
        let installedReference = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)/references/evaluation-questions.md"
        )
        #expect(try Data(contentsOf: installedReference)
            == InstallationFixture.evaluationQuestionsData)
        try Data("independent edit\n".utf8).write(to: firstEntry, options: .atomic)
        #expect(try String(contentsOf: secondEntry, encoding: .utf8)
            == InstallationFixture.validSkillSource)
    }

    @Test("Traversal-shaped, nested, linked, executable, and scripted resources fail closed")
    func rejectsUnsafeResourceShapes() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let installer = ResearchSkillInstallationStore()

        let metadata = fixture.source.appendingPathComponent(".DS_Store")
        try Data("unsupported\n".utf8).write(to: metadata)
        do {
            _ = try await installer.stage(directoryURL: fixture.source)
            Issue.record("An unsupported fifth top-level entry was accepted.")
        } catch let error as ResearchSkillInstallationError {
            #expect(error == .unsupportedResource(".DS_Store"))
        }
        try FileManager.default.removeItem(at: metadata)

        let nested = fixture.source
            .appendingPathComponent("references/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested\n".utf8).write(to: nested.appendingPathComponent("escape.md"))
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try FileManager.default.removeItem(at: nested)

        let outside = fixture.root.appendingPathComponent("outside.md")
        try Data("outside\n".utf8).write(to: outside)
        let linked = fixture.source.appendingPathComponent("references/linked.md")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try FileManager.default.removeItem(at: linked)

        let executable = fixture.source.appendingPathComponent("templates/executable.txt")
        try Data("plain text\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try FileManager.default.removeItem(at: executable)

        let script = fixture.source.appendingPathComponent("templates/run.sh")
        try Data("echo unsafe\n".utf8).write(to: script)
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
    }

    @Test("Invalid UTF-8, oversize files, and malformed metadata are rejected")
    func rejectsInvalidBytesAndMetadata() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let installer = ResearchSkillInstallationStore()

        let invalidUTF8 = fixture.source.appendingPathComponent("references/invalid.md")
        try Data([0x66, 0x6f, 0x80]).write(to: invalidUTF8)
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try FileManager.default.removeItem(at: invalidUTF8)

        let oversized = fixture.source.appendingPathComponent("references/oversized.md")
        try Data(
            repeating: 0x61,
            count: ResearchSkillInstallationPreparation.maximumFileUTF8ByteCount + 1
        ).write(to: oversized)
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        try FileManager.default.removeItem(at: oversized)

        for index in 0..<126 {
            try Data("bounded\n".utf8).write(
                to: fixture.source.appendingPathComponent(
                    "references/count-\(index).md"
                )
            )
        }
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        for index in 0..<126 {
            try FileManager.default.removeItem(
                at: fixture.source.appendingPathComponent(
                    "references/count-\(index).md"
                )
            )
        }

        for index in 0..<9 {
            try Data(
                repeating: 0x61,
                count: ResearchSkillInstallationPreparation.maximumFileUTF8ByteCount
            ).write(
                to: fixture.source.appendingPathComponent("references/bulk-\(index).md")
            )
        }
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
        for index in 0..<9 {
            try FileManager.default.removeItem(
                at: fixture.source.appendingPathComponent("references/bulk-\(index).md")
            )
        }

        try Data("---\nname: [unterminated\n---\nBody\n".utf8).write(
            to: fixture.source.appendingPathComponent("SKILL.md"),
            options: .atomic
        )
        await #expect(throws: ResearchSkillInstallationError.self) {
            _ = try await installer.stage(directoryURL: fixture.source)
        }
    }

    @Test("A destination collision prevents every selected Triptych mutation")
    func collisionPreflightMutatesNothing() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let first = ResearchSkillStore(controlURL: fixture.firstControl)
        let second = ResearchSkillStore(controlURL: fixture.secondControl)
        _ = try await first.installDefaultWorkingMethods()
        _ = try await second.installDefaultWorkingMethods()
        _ = try await second.create(
            id: fixture.packageID,
            source: InstallationFixture.validSkillSource
        )
        let installer = ResearchSkillInstallationStore()
        let preparation = try await installer.stage(directoryURL: fixture.source)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await installer.install(
                preparation,
                destinations: [
                    ResearchSkillInstallationDestination(
                        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        skillStore: first
                    ),
                    ResearchSkillInstallationDestination(
                        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                        skillStore: second
                    ),
                ]
            )
        }
        await #expect(throws: ResearchSkillError.self) {
            _ = try await first.package(id: fixture.packageID)
        }
        #expect(try await second.package(id: fixture.packageID).source
            == InstallationFixture.validSkillSource)
    }

    @Test("A later destination failure rolls back every published package")
    func partialInstallRollsBack() async throws {
        enum InjectedFailure: Error { case afterFirstInstall }

        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let first = ResearchSkillStore(controlURL: fixture.firstControl)
        let second = ResearchSkillStore(controlURL: fixture.secondControl)
        _ = try await first.installDefaultWorkingMethods()
        _ = try await second.installDefaultWorkingMethods()
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                if case .afterDestinationInstalled = point {
                    throw InjectedFailure.afterFirstInstall
                }
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        await #expect(throws: InjectedFailure.self) {
            _ = try await installer.install(
                preparation,
                destinations: [
                    ResearchSkillInstallationDestination(
                        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        skillStore: first
                    ),
                    ResearchSkillInstallationDestination(
                        triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                        skillStore: second
                    ),
                ]
            )
        }
        for store in [first, second] {
            await #expect(throws: ResearchSkillError.self) {
                _ = try await store.package(id: fixture.packageID)
            }
        }
        for control in [fixture.firstControl, fixture.secondControl] {
            let names = try FileManager.default.contentsOfDirectory(
                atPath: control.appendingPathComponent("skills").path
            )
            #expect(!names.contains(fixture.packageID))
            #expect(!names.contains { $0.hasPrefix(".working-install-") })
        }
    }

    @Test("Rollback preserves an externally replaced identical package and requires recovery")
    func changedPackageIsNeverDeletedByRollback() async throws {
        enum InjectedFailure: Error { case afterExternalChange }

        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let installedPackage = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)",
            isDirectory: true
        )
        let displacedPackage = fixture.root.appendingPathComponent(
            "externally-displaced-package",
            isDirectory: true
        )
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                guard case .afterDestinationInstalled = point else { return }
                try FileManager.default.moveItem(
                    at: installedPackage,
                    to: displacedPackage
                )
                try FileManager.default.copyItem(
                    at: displacedPackage,
                    to: installedPackage
                )
                throw InjectedFailure.afterExternalChange
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        do {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
            Issue.record("A changed package was reported as rolled back.")
        } catch let error as ResearchSkillInstallationError {
            guard case .destinationRecoveryRequired = error else {
                Issue.record("Unexpected installation error: \(error)")
                return
            }
        }
        let installedEntry = installedPackage.appendingPathComponent("SKILL.md")
        #expect(FileManager.default.fileExists(atPath: installedEntry.path))
        #expect(try String(contentsOf: installedEntry, encoding: .utf8)
            == InstallationFixture.validSkillSource)
    }

    @Test("Dangling current and retained bindings prevent disabled installation")
    func danglingBindingsPreventInstallation() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage(
            skillSource: InstallationFixture.validMethodSkillSource
        )

        let current = ResearchSkillStore(controlURL: fixture.firstControl)
        let currentBinding = try await current.installDefaultWorkingMethods()
        _ = try await current.create(
            id: fixture.packageID,
            source: InstallationFixture.validMethodSkillSource
        )
        _ = try await current.activateResearcherSkill(
            packageID: fixture.packageID,
            for: .critique,
            expectedBindingRevision: currentBinding.revision
        )
        try FileManager.default.removeItem(
            at: fixture.firstControl.appendingPathComponent(
                "skills/\(fixture.packageID)"
            )
        )

        let installer = ResearchSkillInstallationStore()
        let currentPreparation = try await installer.stage(directoryURL: fixture.source)
        do {
            _ = try await installer.install(
                currentPreparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: current
                )]
            )
            Issue.record("A dangling current binding activated a staged package.")
        } catch let error as ResearchSkillInstallationError {
            #expect(error == .destinationBindingConflict(fixture.packageID))
        }

        let retained = ResearchSkillStore(controlURL: fixture.secondControl)
        _ = try await retained.installDefaultWorkingMethods()
        let ignoredRetainedDocument = """
        {
          "schema_version": 1,
          "function_bindings": {"critique": "\(fixture.packageID)"},
          "function_skill_bindings": {},
          "function_practice_bindings": {},
          "citation_binding": null,
          "citation_style": null,
          "bibliography_method_binding": null
        }
        """
        try Data(ignoredRetainedDocument.utf8).write(to: retained.bindingsURL)
        let ignoredPreparation = try await installer.stage(directoryURL: fixture.source)
        _ = try await installer.install(
            ignoredPreparation,
            destinations: [ResearchSkillInstallationDestination(
                triptychID: UUID(),
                skillStore: retained
            )]
        )
        try FileManager.default.removeItem(
            at: fixture.secondControl.appendingPathComponent(
                "skills/\(fixture.packageID)"
            )
        )

        let executableRetainedDocument = """
        {
          "schema_version": 1,
          "function_bindings": {},
          "function_skill_bindings": {},
          "function_practice_bindings": {},
          "citation_binding": null,
          "citation_style": null,
          "bibliography_method_binding": "\(fixture.packageID)"
        }
        """
        try Data(executableRetainedDocument.utf8).write(to: retained.bindingsURL)
        let retainedPreparation = try await installer.stage(directoryURL: fixture.source)
        do {
            _ = try await installer.install(
                retainedPreparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: retained
                )]
            )
            Issue.record("A dangling retained binding activated a staged package.")
        } catch let error as ResearchSkillInstallationError {
            #expect(error == .destinationBindingConflict(fixture.packageID))
        }
    }

    @Test("A post-publish hard link fails closed and is quarantined")
    func postPublishHardLinkFailsClosed() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let installedEntry = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)/SKILL.md"
        )
        let linkedEntry = fixture.root.appendingPathComponent("published-hard-link.md")
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                guard case .afterPackagePublished = point else { return }
                try FileManager.default.linkItem(at: installedEntry, to: linkedEntry)
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        do {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
            Issue.record("A post-publication hard link was installed.")
        } catch let error as ResearchSkillInstallationError {
            #expect(error == .unsupportedResource("SKILL.md"))
        }
        await #expect(throws: ResearchSkillError.self) {
            _ = try await destination.package(id: fixture.packageID)
        }
        #expect(try fixture.installRecoveryDirectories(in: fixture.firstControl).count == 1)
    }

    @Test("A post-publish executable bit fails closed and is quarantined")
    func postPublishExecutableFailsClosed() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let installedEntry = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)/SKILL.md"
        )
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                guard case .afterPackagePublished = point else { return }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: installedEntry.path
                )
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        do {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
            Issue.record("A post-publication executable file was installed.")
        } catch let error as ResearchSkillInstallationError {
            #expect(error == .executableResource("SKILL.md"))
        }
        await #expect(throws: ResearchSkillError.self) {
            _ = try await destination.package(id: fixture.packageID)
        }
        #expect(try fixture.installRecoveryDirectories(in: fixture.firstControl).count == 1)
    }

    @Test("A moved package cannot be reported as rolled back")
    func movedPackageRequiresRecovery() async throws {
        enum InjectedFailure: Error { case moved }

        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let installedPackage = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)",
            isDirectory: true
        )
        let displacedPackage = fixture.root.appendingPathComponent(
            "externally-moved-package",
            isDirectory: true
        )
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                guard case .afterDestinationInstalled = point else { return }
                try FileManager.default.moveItem(
                    at: installedPackage,
                    to: displacedPackage
                )
                throw InjectedFailure.moved
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        do {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
            Issue.record("A moved package was reported as rolled back.")
        } catch let error as ResearchSkillInstallationError {
            guard case .destinationRecoveryRequired = error else {
                Issue.record("Unexpected installation error: \(error)")
                return
            }
        }
        #expect(FileManager.default.fileExists(
            atPath: displacedPackage.appendingPathComponent("SKILL.md").path
        ))
    }

    @Test("A replaced Skills root cannot be reported as rolled back")
    func replacedSkillsRootRequiresRecovery() async throws {
        enum InjectedFailure: Error { case replacedRoot }

        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let skillsRoot = fixture.firstControl.appendingPathComponent(
            "skills",
            isDirectory: true
        )
        let displacedRoot = fixture.root.appendingPathComponent(
            "externally-moved-skills-root",
            isDirectory: true
        )
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                guard case .afterDestinationInstalled = point else { return }
                try FileManager.default.moveItem(at: skillsRoot, to: displacedRoot)
                try FileManager.default.createDirectory(
                    at: skillsRoot,
                    withIntermediateDirectories: false
                )
                throw InjectedFailure.replacedRoot
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        do {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
            Issue.record("A displaced Skills root was reported as rolled back.")
        } catch let error as ResearchSkillInstallationError {
            guard case .destinationRecoveryRequired = error else {
                Issue.record("Unexpected installation error: \(error)")
                return
            }
        }
        #expect(FileManager.default.fileExists(
            atPath: displacedRoot.appendingPathComponent(
                "\(fixture.packageID)/SKILL.md"
            ).path
        ))
    }

    @Test("A late descriptor write survives rollback quarantine")
    func lateWriteSurvivesRollbackQuarantine() async throws {
        enum InjectedFailure: Error { case afterInstall }

        let fixture = try InstallationFixture()
        defer { fixture.remove() }
        try fixture.writeValidPackage()
        let destination = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await destination.installDefaultWorkingMethods()
        let state = LateInstallationWriter()
        let installedEntry = fixture.firstControl.appendingPathComponent(
            "skills/\(fixture.packageID)/SKILL.md"
        )
        let installer = ResearchSkillInstallationStore(
            hooks: ResearchSkillInstallationHooks { point in
                switch point {
                case .afterDestinationInstalled:
                    try state.open(installedEntry)
                    throw InjectedFailure.afterInstall
                case .afterRollbackQuarantined:
                    try state.append("Late external write\n")
                case .afterPackagePublished:
                    break
                }
            }
        )
        let preparation = try await installer.stage(directoryURL: fixture.source)

        await #expect(throws: InjectedFailure.self) {
            _ = try await installer.install(
                preparation,
                destinations: [ResearchSkillInstallationDestination(
                    triptychID: UUID(),
                    skillStore: destination
                )]
            )
        }
        state.close()
        let recovery = try #require(
            fixture.installRecoveryDirectories(in: fixture.firstControl).first
        )
        let recoveredSource = try String(
            contentsOf: recovery.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        #expect(recoveredSource.hasSuffix("Late external write\n"))
    }
}

private struct InstallationFixture {
    static let evaluationQuestionsData = Data([0xEF, 0xBB, 0xBF])
        + Data("# Evaluation questions\n".utf8)

    static let validSkillSource = """
    ---
    name: Counterexample Stress Test
    description: Pressure-test a philosophical claim with counterexamples.
    scholium:
      role: specialist
      supported_actions: [critique]
      capabilities: []
      supported_modes: [review]
      required_skills: []
    ---
    Reconstruct the claim charitably before proposing counterexamples.
    """ + "\n"

    static let validMethodSkillSource = """
    ---
    name: Counterexample Stress Test
    description: Pressure-test a philosophical claim with counterexamples.
    scholium:
      role: method
      supported_actions: [critique]
      supported_functions: [critique]
      capabilities: []
      supported_modes: [review]
      required_skills: []
    ---
    Reconstruct the claim charitably before proposing counterexamples.
    """ + "\n"

    let root: URL
    let source: URL
    let firstControl: URL
    let secondControl: URL
    let packageID = "counterexample-stress-test"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumSkillInstallation-\(UUID().uuidString)",
            isDirectory: true
        )
        source = root.appendingPathComponent(packageID, isDirectory: true)
        firstControl = root.appendingPathComponent("First/.scholium", isDirectory: true)
        secondControl = root.appendingPathComponent("Second/.scholium", isDirectory: true)
        for directory in [
            source.appendingPathComponent("references", isDirectory: true),
            source.appendingPathComponent("templates", isDirectory: true),
            source.appendingPathComponent("evals", isDirectory: true),
            firstControl,
            secondControl,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    func writeValidPackage(
        skillSource: String = Self.validSkillSource
    ) throws {
        try Data(skillSource.utf8).write(
            to: source.appendingPathComponent("SKILL.md")
        )
        try Self.evaluationQuestionsData.write(
            to: source.appendingPathComponent("references/evaluation-questions.md")
        )
        try Data("# Strong objection fixture\n".utf8).write(
            to: source.appendingPathComponent("evals/strong-objection.md")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func installRecoveryDirectories(in controlURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: controlURL.appendingPathComponent("skills", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".install-recovery-") }
    }
}

private final class LateInstallationWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    func open(_ url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let opened = Darwin.open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard opened >= 0 else { throw POSIXError(.EIO) }
        descriptor = opened
    }

    func append(_ source: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0,
              lseek(descriptor, 0, SEEK_END) >= 0 else {
            throw POSIXError(.EBADF)
        }
        let data = Data(source.utf8)
        let written = data.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == data.count, fsync(descriptor) == 0 else {
            throw POSIXError(.EIO)
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }
}
