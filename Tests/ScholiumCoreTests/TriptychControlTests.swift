import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Portable Triptych control directory")
struct TriptychControlTests {

    @Test("Portable attachment records retain only stable identity and typed location")
    func attachmentCatalogRegistrationAndRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultIDs = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        )
        _ = try await store.bootstrap(vaultIDs: vaultIDs)
        let vaultID = try #require(vaultIDs[.output])
        let path = try AttachmentRelativePath("Attachments/id/Figure.png")
        let preferredID = UUID()

        let first = try await store.registerAttachment(
            vaultID: vaultID,
            location: .vaultRelative(path),
            preferredID: preferredID
        )
        let reused = try await store.registerAttachment(
            vaultID: vaultID,
            location: .vaultRelative(path),
            preferredID: UUID()
        )

        #expect(first.created)
        #expect(first.record.id == preferredID)
        #expect(!reused.created)
        #expect(reused.record == first.record)
        #expect(try await store.attachmentRecords() == [first.record])
        let recordURL = fixture.root
            .appendingPathComponent(".scholium/attachments/v2")
            .appendingPathComponent("\(preferredID.uuidString.lowercased()).json")
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: recordURL))
                as? [String: Any]
        )
        #expect(Set(object.keys) == ["schemaVersion", "id", "vaultID", "location"])

        try await store.removeAttachment(first.record)
        #expect(try await store.attachmentRecords().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: recordURL.path))
    }

    @Test("Legacy attachment catalogs remain opaque and cannot be bootstrapped")
    func legacyAttachmentCatalogIsNotReused() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = fixture.root
            .appendingPathComponent(".scholium/attachments/v1", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let bytes = Data(#"{"schemaVersion":1,"legacy":true}"#.utf8)
        let record = legacy.appendingPathComponent("legacy.json")
        try bytes.write(to: record, options: .withoutOverwriting)
        let store = TriptychControlStore(worksVaultURL: fixture.works)

        await #expect(throws: TriptychControlError.self) {
            _ = try await store.bootstrap(
                vaultIDs: Dictionary(
                    uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
                ))
        }
        #expect(try Data(contentsOf: record) == bytes)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent(".scholium/manifest.json").path
            ))
    }

    @Test("Current attachment catalogs are validated before use")
    func invalidCurrentAttachmentCatalogIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultIDs = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        )
        _ = try await store.bootstrap(vaultIDs: vaultIDs)
        let catalog = fixture.root
            .appendingPathComponent(".scholium/attachments/v2", isDirectory: true)
        let id = UUID()
        let recordURL = catalog.appendingPathComponent(
            "\(id.uuidString.lowercased()).json"
        )
        let bytes = Data(#"{"schemaVersion":1,"legacy":true}"#.utf8)
        try bytes.write(to: recordURL, options: .withoutOverwriting)
        let manifestURL = fixture.root.appendingPathComponent(
            ".scholium/manifest.json"
        )
        let manifestBefore = try Data(contentsOf: manifestURL)

        do {
            try await store.validateExistingSupportedControlState()
            Issue.record("A malformed current attachment catalog must be rejected.")
        } catch let error as TriptychControlError {
            guard case .invalidAttachmentCatalog = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        do {
            _ = try await store.bootstrap(vaultIDs: vaultIDs)
            Issue.record("Bootstrap must reject a malformed current catalog before writing.")
        } catch let error as TriptychControlError {
            guard case .invalidAttachmentCatalog = error else {
                Issue.record("Unexpected bootstrap error: \(error)")
                return
            }
        }
        #expect(try Data(contentsOf: recordURL) == bytes)
        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    }

    @Test("Portable Settings schema has one bounded set of owners")
    func portableSettingsSchemaOwners() throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(TriptychSettings()))
                as? [String: Any]
        )

        #expect(
            Set(object.keys) == [
                "schemaVersion",
                "attentionDismissalDays",
            ])
        #expect((object["schemaVersion"] as? NSNumber)?.intValue == 9)
    }

    @Test("The isolated QA Settings fixture uses only the current schema")
    func qaSettingsFixtureUsesCurrentSchema() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Tools/Fixtures/qa-triptych-settings-v9.json"
            ))
        let settings = try JSONDecoder().decode(TriptychSettings.self, from: data)

        #expect(settings.schemaVersion == TriptychSettings.currentSchemaVersion)
        try TriptychSettingsValidator.validate(settings)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(
            Set(object.keys) == [
                "schemaVersion",
                "attentionDismissalDays",
            ])
    }

    @Test("Settings save rejects a stale exact-byte revision without overwriting")
    func settingsRevisionConflict() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)
        let initial = try await store.settings()

        var first = initial.settings
        first.attentionDismissalDays = 14
        let committed = try await store.saveSettings(first, expectedRevision: initial.revision)

        var staleCandidate = initial.settings
        staleCandidate.attentionDismissalDays = 30
        await #expect(throws: TriptychControlError.self) {
            try await store.saveSettings(staleCandidate, expectedRevision: initial.revision)
        }
        #expect(try await store.settings() == committed)
    }

    @Test("Settings compiler rejects authored About fields before write")
    func settingsCompilerRejectsInvalidCandidates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))
        let initial = try await store.settings()
        var invalid = initial.settings
        invalid.attentionDismissalDays = 0

        do {
            _ = try await store.saveSettings(invalid, expectedRevision: initial.revision)
            Issue.record("An invalid settings candidate was written.")
        } catch let error as TriptychControlError {
            guard case .settingsNeedsReview = error else {
                Issue.record("Unexpected settings error: \(error)")
                return
            }
        }
        #expect(try await store.settings() == initial)
    }

    @Test("Settings loader distinguishes old, future, corrupt, and current-schema review states")
    func settingsFailureStatesRemainDistinct() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))
        let url = fixture.root.appendingPathComponent(".scholium/settings.json")

        var invalidObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(TriptychSettings()))
                as? [String: Any]
        )
        invalidObject["attentionDismissalDays"] = 0
        let invalidBytes = try JSONSerialization.data(withJSONObject: invalidObject)
        try invalidBytes.write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsNeedsReview = $0 { true } else { false } })
        #expect(try Data(contentsOf: url) == invalidBytes)

        try Data(#"{"properties":{}}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsOldSchema(nil) = $0 { true } else { false } })

        try Data(#"{"schemaVersion":999}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsFutureSchema(999) = $0 { true } else { false } })

        let oldSchemaBytes = Data(
            #"{"schemaVersion":3,"promptTemplates":[],"activePromptTemplateIDs":{}}"#.utf8
        )
        try oldSchemaBytes.write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsOldSchema(3) = $0 { true } else { false } })
        #expect(try Data(contentsOf: url) == oldSchemaBytes)

        try Data(#"{"schemaVersion":9,"attentionDismissalDays":"damaged"}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsCorrupted = $0 { true } else { false } })

        var reviewedObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(TriptychSettings()))
                as? [String: Any]
        )
        reviewedObject["attentionDismissalDays"] = 0
        try JSONSerialization.data(withJSONObject: reviewedObject)
            .write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsNeedsReview = $0 { true } else { false } })
    }

    @Test("Typed Settings load preserves repairable data and distinguishes unavailable states")
    func typedSettingsLoadState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))
        let url = fixture.root.appendingPathComponent(".scholium/settings.json")

        var reviewableObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(TriptychSettings()))
                as? [String: Any]
        )
        reviewableObject["attentionDismissalDays"] = 0
        let reviewableBytes = try JSONSerialization.data(withJSONObject: reviewableObject)
        let reviewable = try JSONDecoder().decode(TriptychSettings.self, from: reviewableBytes)
        try reviewableBytes.write(to: url, options: .atomic)
        guard
            case .needsReview(let decoded, let revision, let reason) =
                try await store.settingsLoadState()
        else {
            Issue.record("Expected a repairable current-schema state.")
            return
        }
        #expect(decoded == reviewable)
        #expect(revision.fingerprint == DocumentFingerprint(data: reviewableBytes))
        #expect(!reason.isEmpty)
        #expect(try Data(contentsOf: url) == reviewableBytes)

        try Data(#"{"properties":{}}"#.utf8).write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .oldSchema(nil))

        try Data(#"{"schemaVersion":999}"#.utf8).write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .futureSchema(999))

        try Data(#"{"schemaVersion":5,"properties":"damaged"}"#.utf8)
            .write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .oldSchema(5))
    }

    @Test("An uncoordinated final-window replacement is preserved instead of overwritten")
    func settingsFinalWindowConflict() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external replacement".utf8)
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { url in try external.write(to: url, options: .atomic) }
        )
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))
        let initial = try await store.settings()
        var candidate = initial.settings
        candidate.attentionDismissalDays = 30

        await #expect(throws: TriptychControlError.self) {
            try await store.saveSettings(candidate, expectedRevision: initial.revision)
        }
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(".scholium/settings.json")) == external)
    }

    @Test("Every post-swap Settings failure is commit-uncertain and rereadable")
    func settingsPostSwapFailureIsTyped() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { _ in },
            controlPostSwapHook: { _ in throw POSIXError(.EIO) }
        )
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))
        let initial = try await store.settings()
        var candidate = initial.settings
        candidate.attentionDismissalDays = 30

        do {
            _ = try await store.saveSettings(
                candidate,
                expectedRevision: initial.revision
            )
            Issue.record("Expected a typed commit-uncertain outcome.")
        } catch let error as TriptychControlError {
            guard case .controlFileCommitUncertain = error else {
                Issue.record("Unexpected control error: \(error)")
                return
            }
        }

        guard case .current(let reread) = try await store.settingsLoadState() else {
            Issue.record("The authoritative Settings file was not rereadable.")
            return
        }
        #expect(reread.settings == candidate)
        #expect(reread.revision != initial.revision)
    }

    @Test("An identity final-window replacement is preserved instead of publishing a false record")
    func identityFinalWindowConflict() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external identity replacement".utf8)
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { url in
                guard url.lastPathComponent == "identities.json" else { return }
                try external.write(to: url, options: .atomic)
            }
        )
        _ = try await store.bootstrap(
            vaultIDs: Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
            ))

        await #expect(throws: TriptychControlError.self) {
            _ = try await store.identity(
                forVaultID: UUID(),
                relativePath: "Untitled.md",
                fingerprint: DocumentFingerprint(content: "")
            )
        }
        #expect(
            try Data(
                contentsOf: fixture.root.appendingPathComponent(
                    ".scholium/identities.json"
                )
            ) == external
        )
    }

    @Test("Bootstrap never replaces an identity file claimed by another process")
    func bootstrapIdentityClaimIsNoReplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let vaultIDs = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        )
        let seedStore = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await seedStore.bootstrap(vaultIDs: vaultIDs)
        let analysisVaultID = try #require(vaultIDs[.paperAnalysis])
        let expected = try #require(
            await seedStore.identity(
                forVaultID: analysisVaultID,
                relativePath: "Concurrent.md",
                fingerprint: DocumentFingerprint(content: "Concurrent")
            ))
        let controlURL = fixture.root.appendingPathComponent(".scholium")
        let identitiesURL = controlURL.appendingPathComponent("identities.json")
        let externallyClaimed = try Data(contentsOf: identitiesURL)
        try FileManager.default.removeItem(at: controlURL)

        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { _ in },
            controlCreateHook: { url in
                guard url.lastPathComponent == "identities.json" else { return }
                try externallyClaimed.write(to: url, options: .withoutOverwriting)
            }
        )
        _ = try await store.bootstrap(vaultIDs: vaultIDs)

        #expect(try Data(contentsOf: identitiesURL) == externallyClaimed)
        #expect(try await store.identityRecord(id: expected.id) == expected)
    }

    @Test("Managed creation replacement cannot overwrite a final-window reserved identity")
    func managedCreationIdentityReplacementRejectsReservedRace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinationURL = fixture.root.appendingPathComponent("Application Support/Triptych")
        let store = try TriptychControlStore(
            worksVaultURL: fixture.works,
            coordinationURL: coordinationURL
        )
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: vaultID,
            .topicKnowledge: UUID(),
            .output: UUID(),
        ])
        let intended = DocumentFingerprint(content: "intended")
        let reserved = NoteIdentityRecord(
            id: UUID(),
            vaultID: vaultID,
            relativePath: "Elsewhere.md",
            fingerprint: DocumentFingerprint(content: "elsewhere")
        )
        let racing = try TriptychControlStore(
            worksVaultURL: fixture.works,
            coordinationURL: coordinationURL,
            controlWriteHook: { url in
                guard url.lastPathComponent == "identities.json" else { return }
                let data = try Data(contentsOf: url)
                var object = try #require(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                var records = try #require(object["records"] as? [[String: Any]])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let encoded = try encoder.encode(reserved)
                records.append(
                    try #require(
                        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                    ))
                object["records"] = records
                try JSONSerialization.data(withJSONObject: object)
                    .write(to: url, options: .atomic)
            }
        )

        await #expect(throws: TriptychControlError.self) {
            try await racing.reconcileManagedCreationIdentity(
                vaultID: vaultID,
                relativePath: "Created.md",
                intendedRevision: intended,
                reservedIdentityID: reserved.id,
                sourceIsPresent: true
            )
        }
        #expect(
            try await store.identityRecord(
                vaultID: vaultID,
                relativePath: "Created.md"
            ) == nil)
        let retainedReserved = try #require(
            try await store.identityRecord(
                id: reserved.id
            ))
        #expect(retainedReserved.vaultID == reserved.vaultID)
        #expect(retainedReserved.relativePath == reserved.relativePath)
        #expect(retainedReserved.fingerprint == reserved.fingerprint)
    }

    @Test("Managed creation recovery never replaces another same-revision identity")
    func managedCreationIdentityRejectsForeignPathIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinationURL = fixture.root.appendingPathComponent("Application Support/Triptych")
        let store = try TriptychControlStore(
            worksVaultURL: fixture.works,
            coordinationURL: coordinationURL
        )
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: vaultID,
            .topicKnowledge: UUID(),
            .output: UUID(),
        ])
        let intended = DocumentFingerprint(content: "identical intended bytes")

        for sourceIsPresent in [true, false] {
            let path = sourceIsPresent ? "Present.md" : "Absent.md"
            let foreign = try #require(
                try await store.identity(
                    forVaultID: vaultID,
                    relativePath: path,
                    fingerprint: intended
                ))
            await #expect(throws: TriptychControlError.self) {
                try await store.reconcileManagedCreationIdentity(
                    vaultID: vaultID,
                    relativePath: path,
                    intendedRevision: intended,
                    reservedIdentityID: UUID(),
                    sourceIsPresent: sourceIsPresent
                )
            }
            #expect(
                try await store.identityRecord(
                    vaultID: vaultID,
                    relativePath: path
                ) == foreign)
        }
    }

    @Test("Bootstrap writes only portable state beside Works")
    func bootstrapPortableState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })

        let manifest = try await store.bootstrap(vaultIDs: ids)

        #expect(manifest.vaultIDs == ids)
        #expect(await store.controlURL == fixture.root.appendingPathComponent(".scholium", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".scholium/manifest.json").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".scholium/analysis-zotero-bindings.json").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".scholium/projects.json").path))

        let data = try Data(contentsOf: fixture.root.appendingPathComponent(".scholium/manifest.json"))
        let source = try #require(String(data: data, encoding: .utf8))
        #expect(!source.contains(fixture.root.path))
    }

    @Test("A new portable manifest adopts the registered Triptych identity")
    func bootstrapUsesPreferredTriptychIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        let preferredID = UUID()

        let created = try await store.bootstrap(
            vaultIDs: ids,
            preferredTriptychID: preferredID
        )
        let reopened = try await store.bootstrap(
            vaultIDs: ids,
            preferredTriptychID: UUID()
        )

        #expect(created.id == preferredID)
        #expect(reopened.id == preferredID)
        #expect(try await store.manifest().id == preferredID)
    }

    @Test("Bootstrap preserves unrecognized researcher control files")
    func bootstrapPreservesUnrecognizedControlFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let unrecognizedData = Data(#"{"custom_records":[{"name":"Researcher data"}]}"#.utf8)
        let unrecognizedURL = control.appendingPathComponent("researcher-custom.json")
        try unrecognizedData.write(to: unrecognizedURL)

        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)

        #expect(try Data(contentsOf: unrecognizedURL) == unrecognizedData)
    }

    @Test("Unsupported portable control is archived as one opaque owner")
    func preserveUnsupportedPortableControlBundle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let analyses = fixture.root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = fixture.root.appendingPathComponent("Topics", isDirectory: true)
        for url in [analyses, topics] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let researchFiles = [
            analyses.appendingPathComponent("Paper.md"),
            topics.appendingPathComponent("Problem.md"),
            fixture.works.appendingPathComponent("Draft.md"),
        ]
        let researchBytes = [Data("analysis".utf8), Data([0, 1, 2]), Data("draft".utf8)]
        for (url, data) in zip(researchFiles, researchBytes) { try data.write(to: url) }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let nested = control.appendingPathComponent("legacy/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let legacyFiles = [
            control.appendingPathComponent("manifest.json"),
            nested.appendingPathComponent("opaque.bin"),
        ]
        let legacyBytes = [Data("{\"schemaVersion\":0}".utf8), Data([0xff, 0x00, 0x7f])]
        for (url, data) in zip(legacyFiles, legacyBytes) { try data.write(to: url) }

        let preserved = try await TriptychControlStore.preserveUnsupportedControlBundle(
            worksVaultURL: fixture.works
        )

        #expect(!FileManager.default.fileExists(atPath: control.path))
        #expect(
            try Data(contentsOf: preserved.appendingPathComponent("manifest.json"))
                == legacyBytes[0])
        #expect(
            try Data(contentsOf: preserved.appendingPathComponent("legacy/nested/opaque.bin"))
                == legacyBytes[1])
        for (url, data) in zip(researchFiles, researchBytes) {
            #expect(try Data(contentsOf: url) == data)
        }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        #expect(try await store.bootstrap(vaultIDs: ids).vaultIDs == ids)
        #expect(
            try Data(contentsOf: preserved.appendingPathComponent("manifest.json"))
                == legacyBytes[0])
        await #expect(throws: ExactStatePreservationError.self) {
            _ = try await TriptychControlStore.preserveUnsupportedControlBundle(
                worksVaultURL: fixture.works
            )
        }
        #expect(try await store.manifest().vaultIDs == ids)
    }

    @Test("Stable identities survive moves and duplicates receive new IDs")
    func stableIdentityRules() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        let ids: [WorkspaceVaultSlot: UUID] = [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ]
        _ = try await store.bootstrap(vaultIDs: ids)
        let fingerprint = DocumentFingerprint(content: "# A\n")
        let original = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "A.md",
                fingerprint: fingerprint
            ))

        let moved = try await store.moveIdentity(
            id: original.id,
            to: "Folder/A.md",
            fingerprint: fingerprint
        )
        let duplicate = try await store.duplicateIdentity(
            from: original.id,
            to: "Folder/A copy.md",
            fingerprint: fingerprint
        )

        #expect(moved.id == original.id)
        #expect(moved.relativePath == "Folder/A.md")
        #expect(duplicate.id != original.id)
        #expect(duplicate.duplicatedFrom == original.id)
        #expect(try await store.pendingIdentityRebindings(vaultID: vaultID).count == 1)
    }

    @Test("Lifecycle identity moves recover a record lost between the file and control writes")
    func lifecycleMoveRecoversMissingIdentityRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let fingerprint = DocumentFingerprint(content: "# Work\n")
        let original = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Work.md",
                fingerprint: fingerprint
            ))
        _ = try await store.purgeIdentity(
            id: original.id,
            vaultID: vaultID,
            relativePath: "Work.md"
        )

        let recovered = try await store.moveIdentity(
            id: original.id,
            vaultID: vaultID,
            from: "Work.md",
            to: "Archive/Work.md",
            fingerprint: fingerprint
        )

        #expect(recovered.id == original.id)
        #expect(recovered.relativePath == "Archive/Work.md")
        let stored = try await store.identityRecord(
            vaultID: vaultID,
            relativePath: "Archive/Work.md"
        )
        #expect(stored?.id == recovered.id)
        #expect(stored?.vaultID == recovered.vaultID)
        #expect(stored?.relativePath == recovered.relativePath)
        #expect(stored?.fingerprint == recovered.fingerprint)
    }

    @Test("Creation rollback purges portable identity and pending rebinding state")
    func creationRollbackPurgesIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let fingerprint = DocumentFingerprint(content: "# Work\n")
        let identity = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Work.md",
                fingerprint: fingerprint
            ))
        _ = try await store.moveIdentity(
            id: identity.id,
            to: "Archive/Work.md",
            fingerprint: fingerprint
        )

        let removed = try await store.purgeIdentity(
            id: identity.id,
            vaultID: vaultID,
            relativePath: "Archive/Work.md"
        )

        #expect(removed?.id == identity.id)
        #expect(try await store.pendingIdentityRebindings(vaultID: vaultID).isEmpty)
        #expect(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Archive/Work.md",
                fingerprint: fingerprint,
                createIfMissing: false
            ) == nil)
    }

    @Test("An external copy cannot steal the identity of a still-present note")
    func copyDoesNotStealIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let fingerprint = DocumentFingerprint(content: "same bytes")
        let original = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Z Original.md",
                fingerprint: fingerprint
            ))

        let result = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [
                ("A Copy.md", fingerprint),
                ("Z Original.md", fingerprint),
            ]
        )

        #expect(result.identities["Z Original.md"]?.id == original.id)
        #expect(result.identities["A Copy.md"]?.id != original.id)
        #expect(result.rebound.isEmpty)
        #expect(result.ambiguities.isEmpty)
    }

    @Test("A unique external rename reports the preserved identity and both paths")
    func uniqueExternalRename() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let fingerprint = DocumentFingerprint(content: "renamed bytes")
        let original = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Before.md",
                fingerprint: fingerprint
            ))

        let result = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [("After.md", fingerprint)]
        )

        #expect(result.identities["After.md"]?.id == original.id)
        #expect(
            result.rebound == [
                NoteIdentityRebinding(
                    id: original.id,
                    previousRelativePath: "Before.md",
                    relativePath: "After.md"
                )
            ])
        #expect(result.ambiguities.isEmpty)
        #expect(result.pendingRebindings.count == 1)
        #expect(result.pendingRebindings.first?.noteID == original.id)
        #expect(result.pendingRebindings.first?.previousRelativePath == "Before.md")

        let pending = try #require(result.pendingRebindings.first)
        try await store.completeIdentityRebinding(pending)
        #expect(try await store.pendingIdentityRebindings(vaultID: vaultID).isEmpty)
    }

    @Test("Ambiguous external renames remain unresolved until the researcher chooses")
    func ambiguousExternalRename() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let fingerprint = DocumentFingerprint(content: "ambiguous bytes")
        let first = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Old A.md",
                fingerprint: fingerprint
            ))
        _ = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Old B.md",
                fingerprint: fingerprint
            ))

        let unresolved = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [("Moved.md", fingerprint)]
        )
        #expect(unresolved.identities["Moved.md"] == nil)
        #expect(unresolved.ambiguities.first?.candidates.count == 2)
        #expect(unresolved.ambiguities.first?.vaultID == vaultID)

        let resolved = try await store.resolveIdentityAmbiguity(
            vaultID: vaultID,
            relativePath: "Moved.md",
            fingerprint: fingerprint,
            candidateID: first.id
        )
        #expect(resolved.id == first.id)
        #expect(resolved.relativePath == "Moved.md")
        let pending = try #require(try await store.pendingIdentityRebindings(vaultID: vaultID).first)
        #expect(pending.noteID == first.id)
        #expect(pending.previousRelativePath == "Old A.md")
        #expect(pending.relativePath == "Moved.md")
        #expect(
            try await store.reconcileIdentityInventory(
                vaultID: vaultID,
                documents: [("Moved.md", fingerprint)]
            ).identities["Moved.md"]?.id == first.id)
    }

    @Test("Identical paths and bytes in different vaults never share identity recovery")
    func identityRecoveryIsVaultQualified() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let analysesID = UUID()
        let topicsID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: analysesID,
            .topicKnowledge: topicsID,
            .output: UUID(),
        ])
        let fingerprint = DocumentFingerprint(content: "same bytes")
        let analysis = try #require(
            try await store.identity(
                forVaultID: analysesID,
                relativePath: "Shared.md",
                fingerprint: fingerprint
            ))
        let topic = try #require(
            try await store.identity(
                forVaultID: topicsID,
                relativePath: "Shared.md",
                fingerprint: fingerprint
            ))

        let analysisResult = try await store.reconcileIdentityInventory(
            vaultID: analysesID,
            documents: [("Moved.md", fingerprint)]
        )

        #expect(analysisResult.identities["Moved.md"]?.id == analysis.id)
        #expect(analysisResult.identities["Moved.md"]?.id != topic.id)
        #expect(analysisResult.pendingRebindings.map(\.vaultID) == [analysesID])
        #expect(try await store.pendingIdentityRebindings(vaultID: topicsID).isEmpty)
    }

    @Test("An unresolved rename stays blocked after its file content changes")
    func ambiguityPersistsAcrossFingerprintChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let vaultID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: vaultID,
        ])
        let originalFingerprint = DocumentFingerprint(content: "same original bytes")
        let first = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "First.md",
                fingerprint: originalFingerprint
            ))
        _ = try #require(
            try await store.identity(
                forVaultID: vaultID,
                relativePath: "Second.md",
                fingerprint: originalFingerprint
            ))
        let initial = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [("Moved.md", originalFingerprint)]
        )
        #expect(initial.ambiguities.first?.candidates.count == 2)

        let editedFingerprint = DocumentFingerprint(content: "edited after ambiguous rename")
        let refreshed = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [("Moved.md", editedFingerprint)]
        )
        #expect(refreshed.identities["Moved.md"] == nil)
        #expect(refreshed.ambiguities.first?.fingerprint == editedFingerprint)
        #expect(refreshed.ambiguities.first?.candidates.count == 2)

        let resolved = try await store.resolveIdentityAmbiguity(
            vaultID: vaultID,
            relativePath: "Moved.md",
            fingerprint: editedFingerprint,
            candidateID: first.id
        )
        #expect(resolved.id == first.id)
        #expect(try await store.pendingIdentityRebindings(vaultID: vaultID).first?.fingerprint == editedFingerprint)
    }

    private func expectSettingsError(
        _ store: TriptychControlStore,
        matching predicate: (TriptychControlError) -> Bool
    ) async {
        do {
            _ = try await store.settings()
            Issue.record("Expected settings loading to fail.")
        } catch let error as TriptychControlError {
            #expect(predicate(error))
        } catch {
            Issue.record("Unexpected settings error: \(error)")
        }
    }

    private struct Fixture {
        let root: URL
        let works: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Triptych-Control-\(UUID().uuidString)", isDirectory: true)
            works = root.appendingPathComponent("Works", isDirectory: true)
            try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class PortableControlWriteBarrier: @unchecked Sendable {
    private let paused = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func pause() {
        paused.signal()
        release.wait()
    }

    func waitUntilPaused() -> Bool {
        paused.wait(timeout: .now() + 10) == .success
    }

    func resume() {
        release.signal()
    }
}
