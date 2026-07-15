import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Portable Triptych control directory")
struct TriptychControlTests {
    @Test("Legacy Critique prompt migrates into the Research Guidance collection")
    func legacyCritiquePromptMigration() throws {
        let data = Data(#"{"critiquePromptTemplate":"Legacy {{critique_scope}} {{critique_lens}} {{selected_ranges}} {{additional_instructions}}"}"#.utf8)
        let settings = try JSONDecoder().decode(TriptychSettings.self, from: data)

        #expect(settings.critiquePromptTemplate.hasPrefix("Legacy"))
        #expect(settings.activePromptTemplate(for: .dialogue).source == TriptychSettings.defaultDialoguePromptTemplate)
        #expect(settings.promptTemplates.count == 3)
        #expect(settings.promptTemplates.first { $0.id == ResearchPromptTemplate.defaultCritique.id } == .defaultCritique)

        var reset = settings
        reset.resetPromptTemplate(for: .critique)
        #expect(reset.critiquePromptTemplate == TriptychSettings.defaultCritiquePromptTemplate)
    }

    @Test("An early mutated bundled identifier migrates to a separate researcher template")
    func mutatedBundledIdentifierMigration() throws {
        var mutated = ResearchPromptTemplate.defaultCritique
        mutated.source = "Early {{critique_scope}} {{critique_lens}} {{selected_ranges}} {{additional_instructions}}"
        mutated.origin = .researcher
        let data = try JSONEncoder().encode(TriptychSettings(
            promptTemplates: [.defaultDialogue, mutated],
            activePromptTemplateIDs: [.dialogue: ResearchPromptTemplate.defaultDialogue.id, .critique: mutated.id]
        ))

        var settings = try JSONDecoder().decode(TriptychSettings.self, from: data)

        #expect(settings.critiquePromptTemplate.hasPrefix("Early"))
        #expect(settings.activePromptTemplate(for: .critique).id != ResearchPromptTemplate.defaultCritique.id)
        settings.resetPromptTemplate(for: .critique)
        #expect(settings.activePromptTemplate(for: .critique) == .defaultCritique)
    }

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
        #expect(settings.activePromptTemplate(for: .dialogue).source.localizedCaseInsensitiveContains("academic change summary"))
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
            visibleFields: [" status ", "title", "status", "", "authors"],
            editableFields: ["title", " title ", "tags"]
        )

        #expect(configuration.visibleFields == ["status", "title", "authors"])
        #expect(configuration.editableFields == ["title", "tags"])

        configuration.moveVisibleField("authors", to: 0)
        configuration.setVisible(true, field: " year ")
        configuration.setVisible(false, field: "title")
        configuration.editableFields.append(" tags ")

        #expect(configuration.visibleFields == ["authors", "status", "year"])
        #expect(configuration.editableFields == ["title", "tags"])
    }

    @Test("Legacy Properties configuration decodes with a collapsed disclosure default")
    func legacyPropertiesConfigurationDecoding() throws {
        let data = Data(#"""
        {
          "visibleFields": ["year", "title", "year"],
          "editableFields": ["title", "tags"]
        }
        """#.utf8)

        let configuration = try JSONDecoder().decode(VaultPropertiesConfiguration.self, from: data)

        #expect(configuration.visibleFields == ["year", "title"])
        #expect(configuration.editableFields == ["title", "tags"])
        #expect(configuration.isExpanded == false)
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
                visibleFields: ["authors", "year", "title"],
                editableFields: ["title", "authors"],
                isExpanded: true
            ),
            .topicKnowledge: VaultPropertiesConfiguration(
                visibleFields: ["aliases", "status"],
                editableFields: [],
                isExpanded: false
            ),
            .output: VaultPropertiesConfiguration(
                visibleFields: ["title", "deadline", "venue"],
                editableFields: ["title", "deadline", "venue"],
                isExpanded: true
            ),
        ])

        try await store.saveSettings(expected)
        let loaded = try await store.settings()

        #expect(loaded.properties == expected.properties)
        #expect(loaded.properties[.paperAnalysis]?.visibleFields == ["authors", "year", "title"])
        #expect(loaded.properties[.topicKnowledge]?.editableFields == [])
        #expect(loaded.properties[.output]?.isExpanded == true)
    }

    @Test("Missing vault Properties entries receive role defaults")
    func propertiesConfigurationCompletesTriptych() {
        let settings = TriptychSettings(properties: [
            .paperAnalysis: VaultPropertiesConfiguration(
                visibleFields: ["title"],
                editableFields: ["title"],
                isExpanded: true
            ),
        ])

        #expect(settings.properties.count == WorkspaceVaultSlot.allCases.count)
        #expect(settings.properties[.paperAnalysis]?.visibleFields == ["title"])
        #expect(settings.properties[.topicKnowledge] == TriptychSettings.defaultProperties[.topicKnowledge])
        #expect(settings.properties[.output] == TriptychSettings.defaultProperties[.output])
        #expect(settings.properties[.output]?.visibleFields.contains("kind") == true)
        #expect(settings.properties[.output]?.visibleFields.contains("project") == false)
        #expect(settings.properties[.output]?.editableFields.contains("kind") == true)
        #expect(settings.properties[.output]?.editableFields.contains("project") == false)
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

    @Test("Bootstrap leaves obsolete project records untouched")
    func bootstrapPreservesLegacyProjectFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let legacy = Data(#"{"projects":[{"name":"Researcher data"}]}"#.utf8)
        let legacyURL = control.appendingPathComponent("projects.json")
        try legacy.write(to: legacyURL)

        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)

        #expect(try Data(contentsOf: legacyURL) == legacy)
    }

    @Test("Import preserves originals and resolves name collisions")
    func importCopiesMarkdown() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)
        let source = fixture.root.appendingPathComponent("Outside.md")
        try Data("# Imported\n".utf8).write(to: source)

        let first = try await store.importMarkdown(at: source)
        let second = try await store.importMarkdown(at: source)

        #expect(first.lastPathComponent == "Outside.md")
        #expect(second.lastPathComponent == "Outside 2.md")
        #expect(try String(contentsOf: source, encoding: .utf8) == "# Imported\n")
        #expect(try String(contentsOf: first, encoding: .utf8) == "# Imported\n")
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
        #expect(try await store.externalRenameCandidate(vaultID: vaultID, fingerprint: fingerprint) == nil)
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
        #expect(try await store.reconcileIdentities(
            vaultID: vaultID,
            documents: [("Moved.md", fingerprint)]
        )["Moved.md"]?.id == first.id)
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

    @Test("Unclassified Markdown is editable with revision checks")
    func unclassifiedEditing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychControlStore(worksVaultURL: fixture.works)
        let ids = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { ($0, UUID()) })
        _ = try await store.bootstrap(vaultIDs: ids)
        let source = fixture.root.appendingPathComponent("Outside.md")
        try Data("# Imported\n".utf8).write(to: source)
        _ = try await store.importMarkdown(at: source)

        let original = try await store.loadUnclassified(relativePath: "Outside.md")
        let saved = try await store.saveUnclassified(
            relativePath: "Outside.md",
            content: "# Edited\n",
            expectedRevision: original.fingerprint
        )

        #expect(saved.rawContent == "# Edited\n")
        #expect(try await store.unclassifiedDocuments().map(\.relativePath) == ["Outside.md"])
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await store.saveUnclassified(
                relativePath: "Outside.md",
                content: "# Stale\n",
                expectedRevision: original.fingerprint
            )
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
