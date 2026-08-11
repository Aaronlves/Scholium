import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Portable Triptych control directory")
struct TriptychControlTests {
    @Test("Stored Scholium templates adopt the current bundled response contract")
    func bundledTemplateUpdateDoesNotBecomeResearcherCustomization() throws {
        let encoder = JSONEncoder()
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(TriptychSettings())) as? [String: Any]
        )
        var templates = try #require(object["promptTemplates"] as? [[String: Any]])
        let dialogueIndex = try #require(templates.firstIndex {
            ($0["id"] as? String) == ResearchPromptTemplate.defaultDialogue.id.uuidString
        })
        templates[dialogueIndex]["source"] = "Old bundled {{researcher_instruction}} {{selected_notes}} {{editing_rules}}"
        templates[dialogueIndex]["origin"] = ResearchPromptOrigin.scholium.rawValue
        object["promptTemplates"] = templates
        let data = try JSONSerialization.data(withJSONObject: object)

        let settings = try JSONDecoder().decode(TriptychSettings.self, from: data)

        #expect(settings.activePromptTemplate(for: .dialogue) == .defaultDialogue)
        #expect(settings.activePromptTemplate(for: .dialogue).source.localizedCaseInsensitiveContains("concise attributed academic result"))
        #expect(settings.activePromptTemplate(for: .dialogue).source.localizedCaseInsensitiveContains("authorizes no research-note mutation"))
        #expect(!settings.promptTemplates.contains { $0.name == "Migrated Dialogue" })
    }

    @Test("Deleting an active researcher template restores the Scholium default")
    func deletingActiveTemplateRestoresDefault() {
        var settings = TriptychSettings()
        let custom = ResearchPromptTemplate(
            kind: .dialogue,
            name: "Focused Dialogue",
            source: TriptychSettings.defaultDialoguePromptTemplate + "\nKeep the comparison narrow."
        )
        settings.savePromptTemplate(custom)
        #expect(settings.activePromptTemplate(for: .dialogue).id == custom.id)

        settings.deletePromptTemplate(id: custom.id)

        #expect(settings.activePromptTemplate(for: .dialogue).id == ResearchPromptTemplate.defaultDialogue.id)
    }

    @Test("Prompt validation reports every missing required placeholder")
    func promptValidationRequiresStructuralPlaceholders() {
        let template = ResearchPromptTemplate(kind: .critique, name: "Incomplete", source: "Critique this Work.")

        #expect(template.validationIssues.count == ResearchPromptKind.critique.requiredPlaceholders.count)
        #expect(template.validationIssues.allSatisfy { $0.contains("Missing required placeholder") })
    }

    @Test("Properties configuration preserves order and removes duplicate fields")
    func propertiesConfigurationOrderingAndDeduplication() {
        var configuration = VaultPropertiesConfiguration(
            newNoteYAML: "tags: [draft]\r\n\r\n",
            visibleFields: [" authors ", "publication_date", "authors", "", "type"],
            editableFields: ["title", " title ", "tags"]
        )

        #expect(configuration.newNoteYAML == "tags: [draft]\n\n")
        #expect(configuration.visibleFields == ["authors", "publication_date", "type"])
        #expect(configuration.editableFields == ["title", "tags"])

        configuration.moveVisibleField("type", to: 0)
        configuration.setVisible(true, field: " access ")
        configuration.setVisible(false, field: "publication_date")
        configuration.editableFields.append(" tags ")

        #expect(configuration.visibleFields == ["type", "authors", "access"])
        #expect(configuration.editableFields == ["title", "tags"])
    }

    @Test("Seed normalization preserves keep-chomping trailing blank lines exactly")
    func seedKeepChompingRoundTrip() throws {
        let exact = "summary: |+\r\n  first line\r\n\r\n\r\n# trailing context\r\n\r\n"
        let expected = exact.replacingOccurrences(of: "\r\n", with: "\n")
        var settings = TriptychSettings()
        settings.properties[.paperAnalysis] = VaultPropertiesConfiguration(
            newNoteYAML: exact,
            visibleFields: [],
            editableFields: []
        )
        #expect(settings.properties[.paperAnalysis]?.newNoteYAML == expected)
        try TriptychSettingsValidator.validate(settings)
        let decoded = try JSONDecoder().decode(
            TriptychSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.properties[.paperAnalysis]?.newNoteYAML == expected)
    }

    @Test("Vault-wide Properties settings persist independently for all three vaults")
    func propertiesConfigurationPersistence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)

        let expected = TriptychSettings(properties: [
            .paperAnalysis: VaultPropertiesConfiguration(
                newNoteYAML: "language: en\n",
                visibleFields: ["authors", "publication_date", "type"],
                editableFields: ["title", "authors"]
            ),
            .topicKnowledge: VaultPropertiesConfiguration(
                visibleFields: ["aliases"],
                editableFields: []
            ),
            .output: VaultPropertiesConfiguration(
                visibleFields: ["work_type", "coauthors"],
                editableFields: ["work_type", "coauthors"]
            ),
        ], analysisAgentCreation: AnalysisAgentCreationConfiguration(
            requiredFieldsBySourceType: [.journalArticle: ["title", "authors"]]
        ))

        let initial = try await store.settings()
        _ = try await store.saveSettings(expected, expectedRevision: initial.revision)
        let loaded = try await store.settings()

        #expect(loaded.settings.properties == expected.properties)
        #expect(loaded.settings.properties[.paperAnalysis]?.newNoteYAML == "language: en\n")
        #expect(loaded.settings.properties[.paperAnalysis]?.visibleFields == ["authors", "publication_date", "type"])
        #expect(loaded.settings.properties[.topicKnowledge]?.editableFields == [])
        #expect(loaded.settings.properties[.output]?.visibleFields == ["work_type", "coauthors"])
        #expect(loaded.settings.analysisAgentCreation.requiredFields(for: .journalArticle) == ["title", "authors"])
    }

    @Test("Missing vault Properties entries receive role defaults")
    func propertiesConfigurationCompletesTriptych() {
        let settings = TriptychSettings(properties: [
            .paperAnalysis: VaultPropertiesConfiguration(
                visibleFields: ["authors"],
                editableFields: ["title"]
            ),
        ])

        #expect(settings.properties.count == WorkspaceVaultSlot.allCases.count)
        #expect(settings.properties[.paperAnalysis]?.visibleFields == ["authors"])
        #expect(settings.properties[.topicKnowledge] == TriptychSettings.defaultProperties[.topicKnowledge])
        #expect(settings.properties[.output] == TriptychSettings.defaultProperties[.output])
        #expect(settings.properties[.output]?.visibleFields.contains("work_type") == true)
        #expect(settings.properties[.output]?.visibleFields.contains("kind") == false)
        #expect(settings.properties[.output]?.editableFields.contains("coauthors") == true)
        #expect(settings.properties[.output]?.editableFields.contains("authors") == false)
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

    @Test("Settings compiler rejects invalid seeds and Agent requirement collisions before write")
    func settingsCompilerRejectsInvalidCandidates() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(vaultIDs: Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        ))
        let initial = try await store.settings()
        var invalid = initial.settings
        invalid.properties[.paperAnalysis] = VaultPropertiesConfiguration(
            newNoteYAML: "authors:\n  - family: Scanlon\n",
            visibleFields: invalid.properties[.paperAnalysis]?.visibleFields ?? [],
            editableFields: invalid.properties[.paperAnalysis]?.editableFields ?? []
        )
        invalid.analysisAgentCreation = AnalysisAgentCreationConfiguration(
            requiredFieldsBySourceType: [.journalArticle: ["authors"]]
        )

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

    @Test("Settings compiler distinguishes custom seed keys from another role's canonical keys")
    func seedRoleMismatch() throws {
        var settings = TriptychSettings()
        settings.properties[.output] = VaultPropertiesConfiguration(
            newNoteYAML: "doi: custom-looking-but-analysis-canonical\n",
            visibleFields: [],
            editableFields: []
        )
        #expect(throws: TriptychSettingsValidationError.self) {
            try TriptychSettingsValidator.validate(settings)
        }

        settings.properties[.output] = VaultPropertiesConfiguration(
            newNoteYAML: "researcher_method: dialectical\n",
            visibleFields: [],
            editableFields: []
        )
        try TriptychSettingsValidator.validate(settings)
    }

    @Test("Settings loader distinguishes old, future, corrupt, and current-schema review states")
    func settingsFailureStatesRemainDistinct() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(vaultIDs: Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        ))
        let url = fixture.root.appendingPathComponent(".scholium/settings.json")

        var invalidActive = TriptychSettings()
        invalidActive.activePromptTemplateIDs[.dialogue] = UUID()
        let invalidActiveBytes = try JSONEncoder().encode(invalidActive)
        try invalidActiveBytes.write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsNeedsReview = $0 { true } else { false } })
        #expect(try Data(contentsOf: url) == invalidActiveBytes)

        try Data(#"{"properties":{}}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsOldSchema(nil) = $0 { true } else { false } })

        try Data(#"{"schemaVersion":999}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsFutureSchema(999) = $0 { true } else { false } })

        try Data(#"{"schemaVersion":2,"properties":"damaged"}"#.utf8).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsCorrupted = $0 { true } else { false } })

        var reviewed = TriptychSettings()
        reviewed.properties[.paperAnalysis] = VaultPropertiesConfiguration(
            newNoteYAML: "title: reserved\n",
            visibleFields: [],
            editableFields: []
        )
        try JSONEncoder().encode(reviewed).write(to: url, options: .atomic)
        await expectSettingsError(store, matching: { if case .settingsNeedsReview = $0 { true } else { false } })
    }

    @Test("Typed Settings load preserves repairable data and distinguishes unavailable states")
    func typedSettingsLoadState() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await store.bootstrap(vaultIDs: Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        ))
        let url = fixture.root.appendingPathComponent(".scholium/settings.json")
        #expect((try await store.settingsLoadState()).authorizesPropertyEditing)

        var reviewable = TriptychSettings()
        reviewable.activePromptTemplateIDs[.dialogue] = UUID()
        let reviewableBytes = try JSONEncoder().encode(reviewable)
        try reviewableBytes.write(to: url, options: .atomic)
        guard case .needsReview(let decoded, let revision, let reason) =
            try await store.settingsLoadState() else {
            Issue.record("Expected a repairable current-schema state.")
            return
        }
        #expect(decoded == reviewable)
        #expect(revision.fingerprint == DocumentFingerprint(data: reviewableBytes))
        #expect(!reason.isEmpty)
        #expect(!(try await store.settingsLoadState()).authorizesPropertyEditing)
        #expect(try Data(contentsOf: url) == reviewableBytes)

        try Data(#"{"properties":{}}"#.utf8).write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .oldSchema(nil))

        try Data(#"{"schemaVersion":999}"#.utf8).write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .futureSchema(999))

        try Data(#"{"schemaVersion":2,"properties":"damaged"}"#.utf8)
            .write(to: url, options: .atomic)
        #expect(try await store.settingsLoadState() == .corrupted)
        #expect(!(try await store.settingsLoadState()).authorizesPropertyEditing)
    }

    @Test("An uncoordinated final-window replacement is preserved instead of overwritten")
    func settingsFinalWindowConflict() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let external = Data("external replacement".utf8)
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { url in try external.write(to: url, options: .atomic) }
        )
        _ = try await store.bootstrap(vaultIDs: Dictionary(
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
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { _ in },
            controlPostSwapHook: { _ in throw POSIXError(.EIO) }
        )
        _ = try await store.bootstrap(vaultIDs: Dictionary(
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
        let fixture = try Fixture(); defer { fixture.remove() }
        let external = Data("external identity replacement".utf8)
        let store = TriptychControlStore(
            worksVaultURL: fixture.works,
            controlWriteHook: { url in
                guard url.lastPathComponent == "identities.json" else { return }
                try external.write(to: url, options: .atomic)
            }
        )
        _ = try await store.bootstrap(vaultIDs: Dictionary(
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
        let fixture = try Fixture(); defer { fixture.remove() }
        let vaultIDs = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) }
        )
        let seedStore = TriptychControlStore(worksVaultURL: fixture.works)
        _ = try await seedStore.bootstrap(vaultIDs: vaultIDs)
        let analysisVaultID = try #require(vaultIDs[.paperAnalysis])
        let expected = try #require(await seedStore.identity(
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

    @Test("Zotero binding is portable, typed, revision-checked, and independent of YAML")
    func portableZoteroBinding() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)
        let noteID = UUID()
        let initial = try await store.zoteroBindings()
        let binding = try AnalysisZoteroBinding(
            noteID: noteID,
            library: .group(42),
            itemKey: "abcd1234"
        )

        let committed = try await store.setZoteroBinding(
            binding,
            expectedRevision: initial.revision
        )
        #expect(committed.binding(for: noteID)?.itemKey == "ABCD1234")
        #expect(committed.binding(for: noteID)?.library == .group(42))
        await #expect(throws: TriptychControlError.self) {
            try await store.clearZoteroBinding(
                for: noteID,
                expectedRevision: initial.revision
            )
        }

        let cleared = try await store.clearZoteroBinding(
            for: noteID,
            expectedRevision: committed.revision
        )
        #expect(cleared.bindings.isEmpty)
    }

    @Test("Binding decode validates item and library identity")
    func bindingDecodeFailsClosed() throws {
        let noteID = UUID()
        let invalidItem = Data("""
        {"note_id":"\(noteID.uuidString)","library":{"kind":"user"},"item_key":"../bad"}
        """.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AnalysisZoteroBinding.self, from: invalidItem)
        }
        #expect(throws: AnalysisZoteroBindingError.self) {
            try AnalysisZoteroBinding(noteID: noteID, library: .group(0), itemKey: "ABCD")
        }
    }

    @Test("Duplicate copies and permanent purge restore the portable Zotero binding")
    func bindingFollowsIdentityLifecycle() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let analysesID = UUID()
        _ = try await store.bootstrap(vaultIDs: [
            .paperAnalysis: analysesID,
            .topicKnowledge: UUID(),
            .output: UUID(),
        ])
        let fingerprint = DocumentFingerprint(content: "Analysis")
        let original = try #require(try await store.identity(
            forVaultID: analysesID,
            relativePath: "A.md",
            fingerprint: fingerprint
        ))
        let bindingRevision = try await store.zoteroBindings().revision
        _ = try await store.setZoteroBinding(
            try AnalysisZoteroBinding(noteID: original.id, library: .group(42), itemKey: "ABCD"),
            expectedRevision: bindingRevision
        )
        let duplicate = try await store.duplicateIdentity(
            from: original.id,
            to: "A copy.md",
            fingerprint: fingerprint
        )
        #expect(try await store.zoteroBindings().binding(for: duplicate.id)?.library == .group(42))

        let backup = try await store.prepareIdentityPurge(
            id: original.id,
            vaultID: analysesID,
            relativePath: "A.md"
        )
        _ = try await store.purgeIdentity(
            id: original.id,
            vaultID: analysesID,
            relativePath: "A.md"
        )
        #expect(try await store.zoteroBindings().binding(for: original.id) == nil)
        try await store.restorePurgedIdentity(backup)
        #expect(try await store.zoteroBindings().binding(for: original.id)?.itemKey == "ABCD")
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
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".scholium/analysis-zotero-bindings.json").path))
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
        let original = try #require(try await store.identity(
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
        let original = try #require(try await store.identity(
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
            to: "Trash/Work.md",
            fingerprint: fingerprint
        )

        #expect(recovered.id == original.id)
        #expect(recovered.relativePath == "Trash/Work.md")
        let stored = try await store.identityRecord(
            vaultID: vaultID,
            relativePath: "Trash/Work.md"
        )
        #expect(stored?.id == recovered.id)
        #expect(stored?.vaultID == recovered.vaultID)
        #expect(stored?.relativePath == recovered.relativePath)
        #expect(stored?.fingerprint == recovered.fingerprint)
    }

    @Test("Permanent deletion purges portable identity and pending rebinding state")
    func permanentDeletionPurgesIdentity() async throws {
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
        let identity = try #require(try await store.identity(
            forVaultID: vaultID,
            relativePath: "Work.md",
            fingerprint: fingerprint
        ))
        _ = try await store.moveIdentity(
            id: identity.id,
            to: "Trash/Work.md",
            fingerprint: fingerprint
        )

        let removed = try await store.purgeIdentity(
            id: identity.id,
            vaultID: vaultID,
            relativePath: "Trash/Work.md"
        )

        #expect(removed?.id == identity.id)
        #expect(try await store.pendingIdentityRebindings(vaultID: vaultID).isEmpty)
        #expect(try await store.identity(
            forVaultID: vaultID,
            relativePath: "Trash/Work.md",
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
        let original = try #require(try await store.identity(
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
        let original = try #require(try await store.identity(
            forVaultID: vaultID,
            relativePath: "Before.md",
            fingerprint: fingerprint
        ))

        let result = try await store.reconcileIdentityInventory(
            vaultID: vaultID,
            documents: [("After.md", fingerprint)]
        )

        #expect(result.identities["After.md"]?.id == original.id)
        #expect(result.rebound == [NoteIdentityRebinding(
            id: original.id,
            previousRelativePath: "Before.md",
            relativePath: "After.md"
        )])
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
        let first = try #require(try await store.identity(
            forVaultID: vaultID,
            relativePath: "Old A.md",
            fingerprint: fingerprint
        ))
        _ = try #require(try await store.identity(
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
        #expect(try await store.reconcileIdentityInventory(
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
        let analysis = try #require(try await store.identity(
            forVaultID: analysesID,
            relativePath: "Shared.md",
            fingerprint: fingerprint
        ))
        let topic = try #require(try await store.identity(
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
        let first = try #require(try await store.identity(
            forVaultID: vaultID,
            relativePath: "First.md",
            fingerprint: originalFingerprint
        ))
        _ = try #require(try await store.identity(
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
