import Darwin
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Current Research configuration store")
struct ResearchConfigurationStoreTests {
    @Test("Authorized absolute roots open without following a symbolic-link ancestor")
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
        Darwin.close(try SecureResearchConfigurationIO.openAbsoluteDirectory(realControl))

        let linkedParent = fixtureRoot.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent
        )
        #expect(throws: ResearchConfigurationStoreError.self) {
            Darwin.close(try SecureResearchConfigurationIO.openAbsoluteDirectory(
                linkedParent.appendingPathComponent(".scholium", isDirectory: true)
            ))
        }
    }

    @Test("Current owners persist with exact revisions and no retired files")
    func currentOwnersPersist() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let registrations = try ResearchSkillRegistrationDocument(
            registrations: [fixture.registration()]
        )
        let storedRegistrations = try await store.saveRegistrations(
            registrations,
            expectedRevision: nil
        )
        #expect(try await store.registrationSnapshot() == storedRegistrations)

        let profiles = try ResearchAcademicProfileDocument(
            profiles: [fixture.profile()]
        )
        let storedProfiles = try await store.saveProfiles(profiles, expectedRevision: nil)
        #expect(try await store.profileSnapshot() == storedProfiles)

        for retired in [
            "collaboration-policy-v1.json",
            "working-method-bindings-v2.json",
            "research-action-profiles-v1.json",
            "research-permissions-v1.json",
            "skill-registrations-v2.json",
        ] {
            #expect(!FileManager.default.fileExists(atPath: fixture.control
                .appendingPathComponent(retired).path))
        }
        await #expect(throws: ResearchConfigurationStoreError.staleDocument) {
            _ = try await store.saveRegistrations(
                registrations,
                expectedRevision: DocumentFingerprint(content: "stale")
            )
        }
    }

    @Test("Provisioned user Skill files become opaque researcher-owned contents")
    func provisionedSkillsAreOpaqueAfterBootstrap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()

        let initial = try #require(await store.registrationSnapshot())
        #expect(initial.document.registrations.count
            == ResearchActionID.allCases.count)
        let binding = try await store.skillBindingSnapshot(for: .analyze)
        let skillEntry = URL(
            fileURLWithPath: binding.skillFolderPath,
            isDirectory: true
        ).appendingPathComponent("SKILL.md")
        #expect(FileManager.default.fileExists(atPath: skillEntry.path))

        let researcherBytes = Data([0xFF, 0x00, 0x41, 0x0A])
        try researcherBytes.write(to: skillEntry, options: .atomic)
        try await store.bootstrapDefaults()

        #expect(try Data(contentsOf: skillEntry) == researcherBytes)
        let readback = try await store.skillBindingSnapshot(for: .analyze)
        #expect(readback.registrationRevision == initial.revision)
        #expect(readback.skillFolderPath == binding.skillFolderPath)
        #expect(readback.skillFolderIsAvailable)
    }

    @Test("A Skill folder is assignable without any required entry or reference shape")
    func externalFolderRelationIsContentOpaque() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let registrations = try #require(await store.registrationSnapshot())

        let folder = fixture.root.appendingPathComponent(
            "researcher-owned-skill",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let arbitrary = folder.appendingPathComponent("notes.bin")
        let bytes = Data([0x00, 0xFE, 0x7F])
        try bytes.write(to: arbitrary)

        let binding = try await store.registerExternalSkillFolder(
            actionID: .analyze,
            displayName: "Researcher Skill",
            skillFolderPath: folder.path,
            expectedRegistrationRevision: registrations.revision
        )
        #expect(binding.skillFolderPath == folder.path)
        #expect(binding.skillFolderIsAvailable)
        #expect(try Data(contentsOf: arbitrary) == bytes)

        let portable = try Data(contentsOf: fixture.control.appendingPathComponent(
            ResearchConfigurationStore.registrationFileName
        ))
        #expect(!String(decoding: portable, as: UTF8.self).contains(folder.path))
        let local = try Data(contentsOf: fixture.machineStorage.appendingPathComponent(
            ResearchSkillFolderLocatorStore.fileName
        ))
        #expect(String(decoding: local, as: UTF8.self).contains(folder.path))
    }

    @Test("A stale folder assignment changes neither portable nor machine-local state")
    func staleExternalFolderAssignmentRollsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.bootstrapDefaults()
        let snapshot = try #require(await store.registrationSnapshot())
        let folder = try fixture.makeFolder("first")
        let current = try await store.registerExternalSkillFolder(
            actionID: .analyze,
            displayName: "First",
            skillFolderPath: folder.path,
            expectedRegistrationRevision: snapshot.revision
        )
        let registrationBytes = try Data(contentsOf: fixture.control.appendingPathComponent(
            ResearchConfigurationStore.registrationFileName
        ))
        let locatorURL = fixture.machineStorage.appendingPathComponent(
            ResearchSkillFolderLocatorStore.fileName
        )
        let locatorBytes = try Data(contentsOf: locatorURL)

        await #expect(throws: ResearchConfigurationStoreError.staleDocument) {
            _ = try await store.registerExternalSkillFolder(
                actionID: .analyze,
                displayName: "Stale",
                skillFolderPath: try fixture.makeFolder("stale").path,
                expectedRegistrationRevision: snapshot.revision
            )
        }
        #expect(try Data(contentsOf: fixture.control.appendingPathComponent(
            ResearchConfigurationStore.registrationFileName
        )) == registrationBytes)
        #expect(try Data(contentsOf: locatorURL) == locatorBytes)
        #expect(try await store.skillBindingSnapshot(for: .analyze) == current)
    }

    @Test("Machine-local Skill-folder bookmark is folder-scoped")
    func machineLocatorBookmarkLeastPrivilege() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = try fixture.makeFolder("external-skill")
        let recorder = BookmarkAccessRecorder()
        let locator = ResearchSkillFolderLocatorStore(
            storageURL: fixture.machineStorage,
            triptychID: fixture.triptychID,
            bookmarkAccess: recorder.access
        )

        let key = ResearchSkillRegistrationKey()
        let binding = try locator.makeBinding(
            registrationKey: key,
            skillFolderURL: folder
        )
        _ = try locator.save(
            ResearchSkillFolderLocatorStore.Document(
                triptychID: fixture.triptychID,
                bindings: [binding]
            ),
            expectedRevision: nil
        )
        #expect(recorder.createdPaths == [folder.standardizedFileURL.path])
        #expect(recorder.activeAccessCount == 0)
        var access: (any ResearchSkillFolderAccess)? = try locator.skillFolderAccess(
            for: key
        )
        #expect(access?.url.standardizedFileURL.path == folder.path)
        #expect(recorder.activeAccessCount == 1)
        access = nil
        #expect(recorder.activeAccessCount == 0)
    }

    @Test("Invalid machine-local Skill-folder locators are archived before reset")
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
            ResearchSkillFolderLocatorStore.fileName
        )
        let invalid = Data("{\"schemaVersion\":0,\"opaque\":true}".utf8)
        try invalid.write(to: locatorURL)

        #expect(throws: ResearchSkillFolderLocatorError.self) {
            _ = try ResearchSkillFolderLocatorStore(
                storageURL: fixture.machineStorage,
                triptychID: fixture.triptychID
            ).snapshot()
        }
        let preserved = try #require(
            await store.preserveInvalidMachineLocalSkillFolderLocatorsAndReset()
        )
        #expect(try Data(contentsOf: preserved) == invalid)
        let resetSnapshot = try ResearchSkillFolderLocatorStore(
            storageURL: fixture.machineStorage,
            triptychID: fixture.triptychID
        ).snapshot()
        let reset = try #require(resetSnapshot)
        #expect(reset.document.bindings.isEmpty)
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
        let machineStorage: URL
        let triptychID = UUID()

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/research-configuration-fixtures")
                .appendingPathComponent(UUID().uuidString)
            control = root.appendingPathComponent(".scholium", isDirectory: true)
            machineStorage = root.appendingPathComponent(
                "machine/research-guidance",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: control,
                withIntermediateDirectories: true
            )
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
                skillFolder: .triptychControl("skill-folders/analyze")
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

        func makeFolder(_ name: String) throws -> URL {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            return folder
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class BookmarkAccessRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var activeCount = 0

    var createdPaths: [String] {
        lock.withLock { paths }
    }

    var activeAccessCount: Int {
        lock.withLock { activeCount }
    }

    var access: ResearchSkillFolderLocatorStore.BookmarkAccess {
        ResearchSkillFolderLocatorStore.BookmarkAccess(
            create: { [self] url in
                lock.withLock { paths.append(url.standardizedFileURL.path) }
                return Data(url.standardizedFileURL.path.utf8)
            },
            resolve: { data in
                guard let path = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return ResearchSkillFolderLocatorStore.BookmarkResolution(
                    url: URL(fileURLWithPath: path),
                    isStale: false
                )
            },
            start: { [self] _ in
                lock.withLock { activeCount += 1 }
                return true
            },
            stop: { [self] _ in
                lock.withLock { activeCount -= 1 }
            }
        )
    }
}
