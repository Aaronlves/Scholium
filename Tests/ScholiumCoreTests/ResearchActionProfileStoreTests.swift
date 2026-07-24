import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Triptych Research Action Profile storage")
struct ResearchActionProfileStoreTests {
    @Test("A committed Profile write never succeeds through a displaced control path")
    func displacedControlPathIsUncertain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let displacedControl = fixture.root.appendingPathComponent(
            "DisplacedControl",
            isDirectory: true
        )
        let store = ResearchSkillStore(
            controlURL: fixture.firstControl,
            workingMethodHooks: ResearchWorkingMethodStoreHooks { point in
                guard case .afterActionProfileCommit = point else { return }
                try FileManager.default.moveItem(
                    at: fixture.firstControl,
                    to: displacedControl
                )
                try FileManager.default.createDirectory(
                    at: fixture.firstControl,
                    withIntermediateDirectories: true
                )
            }
        )
        _ = try await store.create(
            id: "counterexample-method",
            source: Self.skillSource(actionID: "counterexample-test")
        )

        do {
            _ = try await store.saveActionProfile(
                Self.binding(
                    actionID: "counterexample-test",
                    buttonName: "Stress Test",
                    order: 1
                ),
                expectedDocumentRevision: nil
            )
            Issue.record("A displaced control path was reported as saved.")
        } catch let error as ResearchActionProfileStorageError {
            #expect(error == .unsafeDocument)
        }
        #expect(!FileManager.default.fileExists(
            atPath: store.actionProfileBindingsURL.path
        ))
        #expect(FileManager.default.fileExists(atPath: displacedControl
            .appendingPathComponent("research-action-profiles-v1.json").path))
    }

    @Test("Profiles save, reopen, replace, and reject stale drafts")
    func saveReopenAndStaleDraft() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.firstControl)
        _ = try await store.create(
            id: "counterexample-method",
            source: Self.skillSource(actionID: "counterexample-test")
        )
        let first = try await store.saveActionProfile(
            Self.binding(actionID: "counterexample-test", buttonName: "Stress Test", order: 3),
            expectedDocumentRevision: nil
        )

        let reopened = try #require(try await store.actionProfileSnapshot())
        #expect(reopened == first)
        #expect(reopened.document.orderedBindings.first?.profile.buttonName == "Stress Test")

        let second = try await store.saveActionProfile(
            Self.binding(actionID: "counterexample-test", buttonName: "Test Counterexamples", order: 1),
            expectedDocumentRevision: reopened.revision
        )
        #expect(second.revision != reopened.revision)

        await #expect(throws: ResearchActionProfileStorageError.self) {
            _ = try await store.saveActionProfile(
                Self.binding(actionID: "counterexample-test", buttonName: "Stale", order: 2),
                expectedDocumentRevision: reopened.revision
            )
        }
    }

    @Test("Invalid Profile support fails closed and a bound Skill cannot be deleted")
    func invalidProfileAndBoundDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.firstControl)
        let package = try await store.create(
            id: "counterexample-method",
            source: Self.skillSource(actionID: "counterexample-test")
        )
        let revision = try #require(package.revision)

        await #expect(throws: ResearchActionProfileStorageError.self) {
            _ = try await store.saveActionProfile(
                Self.binding(actionID: "different-test", buttonName: "Different", order: 1),
                expectedDocumentRevision: nil
            )
        }

        _ = try await store.saveActionProfile(
            Self.binding(actionID: "counterexample-test", buttonName: "Stress Test", order: 1),
            expectedDocumentRevision: nil
        )
        await #expect(throws: ResearchActionProfileStorageError.self) {
            try await store.delete(
                id: "counterexample-method",
                expectedRevision: revision
            )
        }
    }

    @Test("Triptychs change only when explicitly copied")
    func independentTriptychCopies() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = ResearchSkillStore(controlURL: fixture.firstControl)
        let second = ResearchSkillStore(controlURL: fixture.secondControl)
        for store in [first, second] {
            _ = try await store.create(
                id: "counterexample-method",
                source: Self.skillSource(actionID: "counterexample-test")
            )
        }
        let initial = try Self.binding(
            actionID: "counterexample-test",
            buttonName: "Stress Test",
            order: 1
        )
        _ = try await first.saveActionProfile(initial, expectedDocumentRevision: nil)
        _ = try await second.saveActionProfile(initial, expectedDocumentRevision: nil)
        let secondBefore = try #require(try await second.actionProfileSnapshot())

        let firstBefore = try #require(try await first.actionProfileSnapshot())
        _ = try await first.saveActionProfile(
            Self.binding(
                actionID: "counterexample-test",
                buttonName: "Revised Stress Test",
                order: 1
            ),
            expectedDocumentRevision: firstBefore.revision
        )

        let unchangedSecond = try #require(try await second.actionProfileSnapshot())
        #expect(unchangedSecond == secondBefore)
        #expect(unchangedSecond.document.orderedBindings.first?.profile.buttonName == "Stress Test")
    }

    @Test("Deleting an unused Skill isolates and archives the exact package")
    func recoverableDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let recoveryRoot = fixture.root.appendingPathComponent(
            "SkillRecovery",
            isDirectory: true
        )
        let store = ResearchSkillStore(
            controlURL: fixture.firstControl,
            workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore(
                snapshotRootURL: recoveryRoot
            )
        )
        let package = try await store.create(
            id: "counterexample-method",
            source: Self.skillSource(actionID: "counterexample-test")
        )
        let revision = try #require(package.revision)

        try await store.delete(id: package.id, expectedRevision: revision)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.package(id: package.id)
        }
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: recoveryRoot
        )
        let listing = try await maintenance.snapshots(packageID: package.id)
        let snapshot = try #require(listing.snapshots.first)
        #expect(snapshot.packageRevision == revision)
        _ = try await maintenance.restore(
            snapshotID: snapshot.id,
            expectedCurrentState: .missing
        )
        #expect(try await store.package(id: package.id).revision == revision)
    }

    @Test("The enabled Manuscript Working Method remains directly editable")
    func editableManuscriptMethod() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(
            controlURL: fixture.firstControl,
            workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore(
                snapshotRootURL: fixture.root.appendingPathComponent(
                    "ManuscriptRecovery",
                    isDirectory: true
                )
            )
        )
        let bindings = try await store.installDefaultWorkingMethods()
        let manuscript = try await store.duplicateBundled(
            id: "scholium-manuscript",
            as: "scholium-working-manuscript"
        )
        let activated = try await store.activateResearcherSkill(
            packageID: manuscript.id,
            for: .manuscript,
            expectedBindingRevision: bindings.revision
        )
        let marker = "\nPreserve the researcher's declared chapter boundary.\n"

        let edited = try await store.saveWorkingMethod(
            for: .manuscript,
            source: manuscript.source + marker,
            expectedPackageRevision: try #require(manuscript.revision),
            expectedBindingRevision: activated.revision
        )

        #expect(edited.source.hasSuffix(marker))
        #expect(try await store.workingMethodBindingSnapshot()?.document
            .binding(for: .manuscript)?.state == .researcherSkill)
    }

    private static func binding(
        actionID: String,
        buttonName: String,
        order: Int
    ) throws -> ResearchActionProfileBinding {
        let id = try #require(ResearchActionID(researcherOwnedRawValue: actionID))
        let profile = try ResearchActionProfile(
            definition: ResearchActionDefinition(
                researcherOwnedID: id,
                executionKind: .critique
            ),
            buttonName: buttonName,
            order: order,
            applicableRoles: [.work],
            showInActions: true,
            modules: [
                .boundedText(
                    id: try #require(ResearchActionModuleID(rawValue: "instruction")),
                    label: "Instruction",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 1_200,
                    allowsMultipleLines: true
                ),
            ],
            sourceRequirement: .none,
            capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.work]),
            feedbackRequirement: .required
        )
        return try ResearchActionProfileBinding(
            packageID: "counterexample-method",
            profile: profile
        )
    }

    private static func skillSource(actionID: String) -> String {
        """
        ---
        name: Counterexample Method
        description: Pressure-test a philosophical claim with explicit counterexamples.
        scholium:
          role: specialist
          supported_actions: [\(actionID)]
          capabilities: []
          supported_modes: [review]
          required_skills: []
        ---
        Reconstruct the claim charitably before proposing counterexamples.
        """ + "\n"
    }

    private struct Fixture {
        let root: URL
        let firstControl: URL
        let secondControl: URL

        init() throws {
            let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            root = repository.appendingPathComponent(
                ".build/session9-profile-tests/\(UUID().uuidString)",
                isDirectory: true
            )
            firstControl = root.appendingPathComponent("First/.scholium", isDirectory: true)
            secondControl = root.appendingPathComponent("Second/.scholium", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
