import Darwin
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Current Research configuration store")
struct ResearchConfigurationStoreTests {
    @Test("Authorized absolute roots open without following any symbolic-link ancestor")
    func absoluteRootOpenRejectsLinkedAncestor() throws {
        let fixtureRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/research-configuration-root-open-fixtures")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let realParent = fixtureRoot.appendingPathComponent("real", isDirectory: true)
        let realControl = realParent.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realControl,
            withIntermediateDirectories: true
        )

        let descriptor = try SecureResearchConfigurationIO.openAbsoluteDirectory(realControl)
        Darwin.close(descriptor)

        let linkedParent = fixtureRoot.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent
        )
        #expect(throws: ResearchConfigurationStoreError.self) {
            let escaped = try SecureResearchConfigurationIO.openAbsoluteDirectory(
                linkedParent.appendingPathComponent(".scholium", isDirectory: true)
            )
            Darwin.close(escaped)
        }
    }

    @Test("Current owners persist with exact revisions and no legacy configuration files")
    func currentOwnersPersist() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let registration = try fixture.registration()
        let registrations = try ResearchSkillRegistrationDocument(
            registrations: [registration]
        )
        let storedRegistrations = try await store.saveRegistrations(
            registrations,
            expectedRevision: nil
        )
        #expect(try await store.registrationSnapshot() == storedRegistrations)

        let profile = try fixture.profile()
        let profiles = try ResearchAcademicProfileDocument(profiles: [profile])
        let storedProfiles = try await store.saveProfiles(
            profiles,
            expectedRevision: nil
        )
        #expect(try await store.profileSnapshot() == storedProfiles)

        let policy = ResearchCollaborationPolicyDocument(
            triptychID: fixture.triptychID,
            policy: .fullAccess
        )
        let storedPolicy = try await store.saveCollaborationPolicy(
            policy,
            expectedRevision: nil
        )
        #expect(try await store.collaborationSnapshot() == storedPolicy)

        #expect(FileManager.default.fileExists(atPath: fixture.control
            .appendingPathComponent(ResearchConfigurationStore.registrationFileName).path))
        #expect(FileManager.default.fileExists(atPath: fixture.control
            .appendingPathComponent(ResearchConfigurationStore.profileFileName).path))
        #expect(FileManager.default.fileExists(atPath: fixture.control
            .appendingPathComponent(ResearchConfigurationStore.collaborationFileName).path))
        for legacy in [
            "working-method-bindings-v2.json",
            "research-action-profiles-v1.json",
            "research-permissions-v1.json",
        ] {
            #expect(!FileManager.default.fileExists(atPath: fixture.control
                .appendingPathComponent(legacy).path))
        }

        await #expect(throws: ResearchConfigurationStoreError.self) {
            _ = try await store.saveRegistrations(
                registrations,
                expectedRevision: DocumentFingerprint(content: "stale")
            )
        }
    }

    @Test("Legacy Practice bytes remain untouched and nonauthorizing")
    func legacyPracticeBytesAreIgnored() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeMethod("""
        # Analyze

        Use [[Dialectical Partner]], then [[Conceptual Analyst]], then
        [[Dialectical Partner]] again. Keep [[Missing Practice]] visible.
        `[[Code Is Not A Link]]`
        [ordinary Markdown](https://example.invalid) is not a Practice.
        """)
        try fixture.writePractice(
            name: "dialectical.md",
            source: "# Dialectical Partner\n\nPreserve objections and replies.\n"
        )
        try fixture.writePractice(
            name: "conceptual.md",
            source: "# Conceptual Analyst\n\nTrack meanings and distinctions.\n"
        )
        let store = fixture.store()
        _ = try await store.saveRegistrations(
            ResearchSkillRegistrationDocument(registrations: [fixture.registration()]),
            expectedRevision: nil
        )

        let legacy = try Data(contentsOf: fixture.practices.appendingPathComponent(
            "dialectical.md"
        ))
        let snapshot = try await store.methodSnapshot(for: .analyze)
        #expect(snapshot.primaryMarkdownSource.contains("[[Dialectical Partner]]"))
        #expect(snapshot.primaryMarkdownRevision == DocumentFingerprint(
            content: snapshot.primaryMarkdownSource
        ))
        #expect(try Data(contentsOf: fixture.practices.appendingPathComponent(
            "dialectical.md"
        )) == legacy)
    }

    @Test("Registered Skill references remain ordinary unenumerated files")
    func skillReferencesAreNotEnumerated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let references = fixture.methods.appendingPathComponent(
            "references", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: references,
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xFE]).write(to: references.appendingPathComponent("lens.md"))
        let store = fixture.store()
        let registration = try ResearchSkillRegistration(
            actionID: .analyze,
            displayName: "Analyze",
            primaryMarkdown: .triptychControl("methods/analyze.md"),
            skillFolder: .triptychControl("methods")
        )
        _ = try await store.saveRegistrations(
            ResearchSkillRegistrationDocument(registrations: [registration]),
            expectedRevision: nil
        )

        let snapshot = try await store.methodSnapshot(for: .analyze)
        #expect(snapshot.skillFolderPath == fixture.methods.path)
        #expect(snapshot.skillFolderIsAvailable == true)
        #expect(try Data(contentsOf: references.appendingPathComponent("lens.md"))
            == Data([0xFF, 0xFE]))
    }

    @Test("Unknown Profile fields and linked method paths fail closed")
    func strictDocumentsAndLinkedMethod() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profile = try fixture.profile()
        var profileObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
                as? [String: Any]
        )
        profileObject["capabilities"] = ["write": true]
        #expect(throws: ResearchAcademicProfileError.self) {
            _ = try JSONDecoder().decode(
                ResearchAcademicActionProfile.self,
                from: try JSONSerialization.data(withJSONObject: profileObject)
            )
        }

        let outside = fixture.root.appendingPathComponent("outside.md")
        try Data("# Outside\n".utf8).write(to: outside)
        let method = fixture.methodURL
        try FileManager.default.removeItem(at: method)
        try FileManager.default.createSymbolicLink(
            at: method,
            withDestinationURL: outside
        )
        let store = fixture.store()
        _ = try await store.saveRegistrations(
            ResearchSkillRegistrationDocument(registrations: [fixture.registration()]),
            expectedRevision: nil
        )
        await #expect(throws: ResearchConfigurationStoreError.self) {
            _ = try await store.methodSnapshot(for: .analyze)
        }
    }

    @Test("A primary Method edit replaces only the expected exact source")
    func primaryMethodEditIsRevisionChecked() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let recoveryURL = fixture.root.appendingPathComponent("machine/recovery.json")
        let store = ResearchConfigurationStore(
            controlURL: fixture.control,
            triptychID: fixture.triptychID
        )
        let registration = try fixture.registration()
        _ = try await store.saveRegistrations(
            ResearchSkillRegistrationDocument(registrations: [registration]),
            expectedRevision: nil
        )
        let original = try await store.methodSnapshot(for: .analyze)
        let edited = try await store.savePrimaryMethod(
            registrationKey: registration.key,
            source: "# Analyze\n\nSecond method.\n",
            expectedRevision: original.primaryMarkdownRevision
        )
        #expect(edited.primaryMarkdownSource == "# Analyze\n\nSecond method.\n")
        #expect(!FileManager.default.fileExists(atPath: recoveryURL.path))
    }

    @Test("A stale Method edit changes neither exact Markdown nor local state")
    func staleMethodEditIsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let recoveryURL = fixture.root.appendingPathComponent("machine/recovery.json")
        let store = ResearchConfigurationStore(
            controlURL: fixture.control,
            triptychID: fixture.triptychID
        )
        let registration = try fixture.registration()
        _ = try await store.saveRegistrations(
            ResearchSkillRegistrationDocument(registrations: [registration]),
            expectedRevision: nil
        )
        let before = try Data(contentsOf: fixture.methodURL)

        await #expect(throws: ResearchConfigurationStoreError.self) {
            _ = try await store.savePrimaryMethod(
                registrationKey: registration.key,
                source: "# Unauthorized replacement\n",
                expectedRevision: DocumentFingerprint(content: "stale")
            )
        }
        #expect(try Data(contentsOf: fixture.methodURL) == before)
        #expect(!FileManager.default.fileExists(atPath: recoveryURL.path))
    }

    @Test("New Triptych bootstrap installs only current defaults and never overwrites an edit")
    func defaultBootstrapIsIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()

        let registrations = try #require(await store.registrationSnapshot())
        let profiles = try #require(await store.profileSnapshot())
        let policy = try #require(await store.collaborationSnapshot())
        #expect(registrations.document.registrations.map(\.actionID) == [
            .analyze, .checkFidelity, .critique, .discuss, .synthesize, .write,
        ])
        #expect(profiles.document.profiles.count == 6)
        #expect(policy.document.policy == .askEveryTime)

        let bundledAnalyze = try BundledResearchMethodDefaults.primarySource(for: .analyze)
        let analyze = try await store.methodSnapshot(for: .analyze)
        #expect(analyze.primaryMarkdownSource == bundledAnalyze)
        #expect(analyze.skillFolderPath != nil)
        let edited = try await store.savePrimaryMethod(
            registrationKey: analyze.registration.key,
            source: "# Researcher Method\n\nKeep this exact edit.\n",
            expectedRevision: analyze.primaryMarkdownRevision
        )

        try await store.bootstrapDefaults()
        #expect(try await store.methodSnapshot(for: .analyze).primaryMarkdownSource
            == edited.primaryMarkdownSource)

        let restored = try await store.restoreDefaultPrimaryMethod(
            actionID: .analyze,
            expectedRevision: edited.primaryMarkdownRevision
        )
        #expect(restored.primaryMarkdownSource == bundledAnalyze)
    }

    @Test("A selected Markdown or folder becomes one exact registration without enumeration")
    func externalRegistrationIsExactAndCASBound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let before = try #require(await store.registrationSnapshot())
        let oldKey = try #require(
            before.document.registration(for: .analyze)
        ).key
        let folder = fixture.root.appendingPathComponent("ordinary-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let primary = folder.appendingPathComponent("primary.md")
        let source = "# Researcher Analyze\n\nUse [[Dialectical Partner]].\n"
        try Data(source.utf8).write(to: primary)
        try Data("opaque sibling".utf8).write(
            to: folder.appendingPathComponent("not-managed.bin")
        )

        let registered = try await store.registerExternalMethod(
            actionID: .analyze,
            displayName: "Researcher Analyze",
            primaryMarkdownPath: primary.path,
            skillFolderPath: folder.path,
            expectedRegistrationRevision: before.revision
        )
        #expect(registered.registration.key != oldKey)
        #expect(registered.primaryMarkdownSource == source)
        #expect(registered.skillFolderPath == folder.path)
        let portableSnapshot = try #require(try await store.registrationSnapshot())
        let portableRegistration = try JSONEncoder().encode(try #require(
            portableSnapshot.document.registration(for: .analyze)
        ))
        #expect(!String(decoding: portableRegistration, as: UTF8.self)
            .contains(folder.path))
        let locatorData = try Data(contentsOf: fixture.machineStorage
            .appendingPathComponent(ResearchMethodLocatorStore.fileName))
        #expect(String(decoding: locatorData, as: UTF8.self).contains(folder.path))
        #expect(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("not-managed.bin").path
        ))

        await #expect(throws: ResearchConfigurationStoreError.staleDocument) {
            _ = try await store.registerExternalMethod(
                actionID: .analyze,
                displayName: "Stale",
                primaryMarkdownPath: primary.path,
                skillFolderPath: folder.path,
                expectedRegistrationRevision: before.revision
            )
        }
        #expect(try await store.methodSnapshot(for: .analyze).registration
            == registered.registration)
    }

    @Test("Creating a Skill commits exact bytes once and stale attempts create nothing")
    func createdMethodIsAtomicAndCASBound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let before = try #require(await store.registrationSnapshot())
        let source = "# My Synthesis\n\nPreserve this exact method.\n"

        let created = try await store.createPrimaryMethod(
            actionID: .synthesize,
            displayName: "My Synthesis",
            source: source,
            expectedRegistrationRevision: before.revision
        )
        #expect(created.primaryMarkdownSource == source)
        #expect(created.skillFolderPath != nil)
        let folders = fixture.control.appendingPathComponent(
            "skill-folders",
            isDirectory: true
        )
        let namesBeforeStale = try FileManager.default.contentsOfDirectory(
            atPath: folders.path
        ).sorted()

        await #expect(throws: ResearchConfigurationStoreError.staleDocument) {
            _ = try await store.createPrimaryMethod(
                actionID: .synthesize,
                displayName: "Stale",
                source: "# Stale\n",
                expectedRegistrationRevision: before.revision
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folders.path).sorted()
            == namesBeforeStale)
        #expect(try await store.methodSnapshot(for: .synthesize).primaryMarkdownSource
            == source)
    }

    @Test("Machine-local Method locators reopen privately and reject Triptych replay")
    func machineLocatorReopenAndIsolation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let before = try #require(await store.registrationSnapshot())
        let folder = fixture.root.appendingPathComponent("external-method")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let method = folder.appendingPathComponent("SKILL.md")
        let source = "# External Analyze\n\nKeep exact source.\n"
        try Data(source.utf8).write(to: method)
        _ = try await store.registerExternalMethod(
            actionID: .analyze,
            displayName: "External Analyze",
            primaryMarkdownPath: method.path,
            skillFolderPath: folder.path,
            expectedRegistrationRevision: before.revision
        )

        let reopened = fixture.store()
        #expect(try await reopened.methodSnapshot(for: .analyze).primaryMarkdownSource
            == source)
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(atPath: fixture.machineStorage.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        let locatorURL = fixture.machineStorage.appendingPathComponent(
            ResearchMethodLocatorStore.fileName
        )
        let fileMode = try #require(
            FileManager.default.attributesOfItem(atPath: locatorURL.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(directoryMode == 0o700)
        #expect(fileMode == 0o600)

        let replayed = ResearchConfigurationStore(
            controlURL: fixture.control,
            triptychID: UUID(),
            machineStorageURL: fixture.machineStorage
        )
        await #expect(throws: ResearchMethodLocatorError.self) {
            _ = try await replayed.methodSnapshot(for: .analyze)
        }
    }

    @Test("Invalid machine-local Method locators are archived before local reset")
    func machineLocatorRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        try FileManager.default.createDirectory(
            at: fixture.machineStorage,
            withIntermediateDirectories: true
        )
        let locatorURL = fixture.machineStorage.appendingPathComponent(
            ResearchMethodLocatorStore.fileName
        )
        let invalid = Data("{\"schemaVersion\":0,\"opaque\":true}".utf8)
        try invalid.write(to: locatorURL)
        let locator = ResearchMethodLocatorStore(
            storageURL: fixture.machineStorage,
            triptychID: fixture.triptychID
        )
        #expect(throws: ResearchMethodLocatorError.self) {
            _ = try locator.snapshot()
        }

        let preserved = try #require(
            try await store.preserveInvalidMachineLocalMethodLocatorsAndReset()
        )

        #expect(try Data(contentsOf: preserved) == invalid)
        let resetData = try Data(contentsOf: locatorURL)
        #expect(resetData != invalid)
        #expect(try await store.preserveInvalidMachineLocalMethodLocatorsAndReset() == nil)
    }

    @Test("Citation style is Triptych-bound, optional, and revision checked")
    func citationStyleSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let initial = try #require(await store.citationMethodSnapshot())
        #expect(initial.document.activeCitationStyle == nil)

        let selected = try await store.saveCitationMethod(
            ResearchCitationMethodDocument(
                triptychID: fixture.triptychID,
                activeCitationStyle: "APA-7"
            ),
            expectedRevision: initial.revision
        )
        #expect(selected.document.activeCitationStyle == "apa-7")
        await #expect(throws: ResearchConfigurationStoreError.staleDocument) {
            _ = try await store.saveCitationMethod(
                ResearchCitationMethodDocument(triptychID: fixture.triptychID),
                expectedRevision: initial.revision
            )
        }
        await #expect(throws: ResearchCitationMethodContractError.triptychMismatch) {
            _ = try await store.saveCitationMethod(
                ResearchCitationMethodDocument(
                    triptychID: UUID(),
                    activeCitationStyle: "apa-7"
                ),
                expectedRevision: selected.revision
            )
        }
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL
        let control: URL
        let methods: URL
        let practices: URL
        let methodURL: URL
        let machineStorage: URL
        let triptychID = UUID()

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/research-configuration-fixtures")
                .appendingPathComponent(UUID().uuidString)
            control = root.appendingPathComponent(".scholium", isDirectory: true)
            methods = control.appendingPathComponent("methods", isDirectory: true)
            practices = control.appendingPathComponent("practices", isDirectory: true)
            methodURL = methods.appendingPathComponent("analyze.md")
            machineStorage = root.appendingPathComponent(
                "machine/research-guidance",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: methods,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: practices,
                withIntermediateDirectories: true
            )
            try writeMethod("# Analyze\n\nDefault method.\n")
        }

        func store() -> ResearchConfigurationStore {
            ResearchConfigurationStore(
                controlURL: control,
                triptychID: triptychID,
                machineStorageURL: machineStorage
            )
        }

        func registration() throws -> ResearchSkillRegistration {
            try ResearchSkillRegistration(
                actionID: .analyze,
                displayName: "Analyze",
                primaryMarkdown: .triptychControl("methods/analyze.md")
            )
        }

        func profile() throws -> ResearchAcademicActionProfile {
            try ResearchAcademicActionProfile(
                actionID: .analyze,
                displayName: "Analyze Note",
                order: 10,
                isEnabled: true,
                applicableRoles: [.analysis],
                academicInputFields: [],
                academicResultFields: [ResearchAcademicFieldDefinition.freeText(
                    id: .academicOutcome,
                    label: "Academic Outcome",
                    requirement: .required
                )]
            )
        }

        func writeMethod(_ source: String) throws {
            try Data(source.utf8).write(to: methodURL, options: .atomic)
        }

        func writePractice(name: String, source: String) throws {
            try Data(source.utf8).write(
                to: practices.appendingPathComponent(name),
                options: .atomic
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
