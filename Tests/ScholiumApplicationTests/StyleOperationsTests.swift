import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Application-owned style I/O")
struct StyleOperationsTests {
    @Test("Named Appearance profiles persist, select, rename, duplicate, and remove")
    func appearanceProfilePersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumAppearanceOperations-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)

        let initial = try await operations.styleSnapshot()
        let original = try #require(initial.appearanceProfiles.first)
        #expect(initial.appearanceProfiles.count == 1)
        #expect(initial.selectedAppearanceProfileID == original.id)
        #expect(original.name == "Custom")
        #expect(original.settings.lineWidthCharacterUnits == 72)
        #expect(original.settings.body.fontSizePoints == 12)
        #expect(original.settings.body.lineHeight == 2)

        var edited = original
        edited.settings.lineWidthCharacterUnits = 84
        edited.settings.body.fontSizePoints = 14.5
        edited.settings.headings.weight = 600
        let orientationIndex = try #require(
            edited.settings.callouts.firstIndex(where: { $0.role == .orientation })
        )
        edited.settings.callouts[orientationIndex].startInsetEm = 4.25
        _ = try await operations.updateAppearanceProfile(edited)
        let renamed = try await operations.renameAppearanceProfile(original.id, to: "Dissertation")
        #expect(renamed.appearanceProfiles.first?.name == "Dissertation")

        let duplicated = try await operations.duplicateAppearanceProfile(original.id)
        let copyID = try #require(duplicated.selectedAppearanceProfileID)
        #expect(duplicated.appearanceProfiles.count == 2)
        #expect(copyID != original.id)
        #expect(duplicated.appearanceProfiles.first(where: { $0.id == copyID })?.name == "Dissertation Copy")

        let reloaded: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let persisted = try await reloaded.styleSnapshot()
        let persistedCopy = try #require(
            persisted.appearanceProfiles.first(where: { $0.id == copyID })
        )
        #expect(persisted.selectedAppearanceProfileID == copyID)
        #expect(persistedCopy.settings.lineWidthCharacterUnits == 84)
        #expect(persistedCopy.settings.body.fontSizePoints == 14.5)
        #expect(persistedCopy.settings.headings.weight == 600)
        #expect(persistedCopy.settings.callout(.orientation).startInsetEm == 4.25)

        let removed = try await reloaded.removeAppearanceProfile(copyID)
        #expect(removed.appearanceProfiles.count == 1)
        #expect(removed.selectedAppearanceProfileID == original.id)
    }

    @Test("Appearance line width normalizes to the supported finite range")
    func appearanceLineWidthNormalization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumAppearanceLineWidth-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let operations: any StyleUseCases = StyleOperations(
            applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true)
        )
        let initial = try await operations.styleSnapshot()
        let original = try #require(initial.appearanceProfiles.first)

        for (input, expected) in [
            (47.0, 48.0),
            (48.0, 48.0),
            (96.0, 96.0),
            (97.0, 96.0),
            (Double.nan, 72.0),
            (Double.infinity, 72.0),
        ] {
            var candidate = original
            candidate.settings.lineWidthCharacterUnits = input
            let snapshot = try await operations.updateAppearanceProfile(candidate)
            #expect(snapshot.appearanceProfiles.first?.settings.lineWidthCharacterUnits == expected)
        }
    }

    @Test("Appearance manifests without line width load with the current default")
    func legacyAppearanceLineWidthDefault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumLegacyAppearanceLineWidth-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let styles = support
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)

        let profile = DocumentAppearanceProfile(name: "Legacy")
        let profileData = try JSONEncoder().encode(profile)
        var profileObject = try #require(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        )
        var settings = try #require(profileObject["settings"] as? [String: Any])
        settings.removeValue(forKey: "lineWidthCharacterUnits")
        profileObject["settings"] = settings
        let manifest = [
            "selectedProfileID": profile.id.uuidString,
            "profiles": [profileObject],
        ] as [String: Any]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try manifestData.write(to: styles.appendingPathComponent("appearances.json"), options: .atomic)

        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let loaded = try await operations.styleSnapshot()
        let legacy = try #require(loaded.appearanceProfiles.first)
        #expect(legacy.settings.lineWidthCharacterUnits == 72)
        #expect(loaded.canModify)

        var updated = legacy
        updated.settings.lineWidthCharacterUnits = 80
        _ = try await operations.updateAppearanceProfile(updated)
        let persistedData = try Data(contentsOf: styles.appendingPathComponent("appearances.json"))
        let persistedText = try #require(String(data: persistedData, encoding: .utf8))
        #expect(persistedText.contains("\"lineWidthCharacterUnits\" : 80"))

        let reloaded: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        #expect(try await reloaded.styleSnapshot().appearanceProfiles.first?.settings.lineWidthCharacterUnits == 80)
    }

    @Test("CSS import and persistence stay behind StyleUseCases")
    func cssPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumStyleOperations-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("Readable.css")
        try Data("p { color: #543210; }\n".utf8).write(to: sourceURL)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)

        let imported = try await operations.importStyleSnippet(from: sourceURL)
        let record = try #require(imported.snippets.first)
        #expect(record.name == "Readable")
        #expect(record.isEnabled)
        #expect(imported.readCSS.contains("#543210"))

        let disabled = try await operations.setStyleSnippetEnabled(false, id: record.id)
        #expect(disabled.snippets.first?.isEnabled == false)
        #expect(disabled.readCSS.isEmpty)
        #expect(try await operations.managedStyleSnippetURL(record.id) != nil)
        #expect(try await operations.managedStylesLocation().path.contains("Application Support"))
    }

    @Test("Obsidian appearance bytes are read in Application")
    func obsidianAppearance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumObsidianAppearance-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let obsidian = root.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidian, withIntermediateDirectories: true)
        try Data(#"{"theme":"moon","showLineNumber":true,"defaultViewMode":"source"}"#.utf8)
            .write(to: obsidian.appendingPathComponent("app.json"))
        let operations = StyleOperations(applicationSupportURL: root.appendingPathComponent("Support"))

        let appearance = try #require(await operations.obsidianAppearance(at: root))
        #expect(appearance.theme == "moon")
        #expect(appearance.showLineNumbers == true)
        #expect(appearance.defaultViewMode == "source")
    }
}
