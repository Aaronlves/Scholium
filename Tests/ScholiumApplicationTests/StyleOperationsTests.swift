import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Application-owned style I/O")
struct StyleOperationsTests {
    @Test("External configuration reload preserves advanced values and prevents a stale UI overwrite")
    func externalAppearanceConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScholiumAppearanceFile-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = StyleOperations(applicationSupportURL: root)
        let initial = try await operations.styleSnapshot()
        var draft = try #require(initial.appearanceProfiles.first)
        let url = try await operations.appearanceConfigurationURL()
        let initialBytes = try Data(contentsOf: url)
        var file = try #require(JSONSerialization.jsonObject(with: initialBytes) as? [String: Any])
        var profiles = try #require(file["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        var headings = try #require(settings["headings"] as? [String: Any])
        headings["weight"] = 650
        settings["headings"] = headings
        profiles[0]["settings"] = settings
        file["profiles"] = profiles
        let external = try JSONSerialization.data(withJSONObject: file, options: .sortedKeys)
        try external.write(to: url, options: .atomic)
        draft.settings.body.fontSizePoints = 16
        await #expect(throws: (any Error).self) { try await operations.updateAppearanceProfile(draft) }
        #expect(try Data(contentsOf: url) == external)
        let reloaded = try await operations.reloadAppearanceConfiguration()
        var current = try #require(reloaded.appearanceProfiles.first)
        #expect(current.settings.headings.weight == 650)
        current.settings.body.fontSizePoints = 15
        let saved = try await operations.updateAppearanceProfile(current)
        #expect(saved.appearanceProfiles.first?.settings.headings.weight == 650)
        #expect(saved.appearanceProfiles.first?.settings.body.fontSizePoints == 15)
    }

    @Test("Invalid external configuration leaves both the file and loaded appearance intact", arguments: ["range", "unknown", "syntax"])
    func invalidConfigurationRetainsAppearance(_ kind: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScholiumInvalidAppearance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = StyleOperations(applicationSupportURL: root)
        let initial = try await operations.styleSnapshot()
        let url = try await operations.appearanceConfigurationURL()
        let original = try Data(contentsOf: url)
        var file = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var profiles = try #require(file["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        settings[kind == "range" ? "lineWidthCharacterUnits" : "misspelledSetting"] = 999
        profiles[0]["settings"] = settings
        file["profiles"] = profiles
        let invalid = kind == "syntax" ? Data("{bad json".utf8) : try JSONSerialization.data(withJSONObject: file)
        try invalid.write(to: url, options: .atomic)
        await #expect(throws: (any Error).self) { try await operations.reloadAppearanceConfiguration() }
        let retained = try await operations.styleSnapshot()
        #expect(retained.appearanceProfiles == initial.appearanceProfiles)
        #expect(try Data(contentsOf: url) == invalid)
        try original.write(to: url, options: .atomic)
        let repaired = try await operations.reloadAppearanceConfiguration()
        #expect(repaired.appearanceProfiles == initial.appearanceProfiles)
    }

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
        #expect(original.settings == DocumentAppearanceSettings.defaultSettings)
        #expect(original.settings.hyphenation == .none)

        var edited = original
        edited.settings.lineWidthCharacterUnits = 84
        edited.settings.body.fontSizePoints = 14.5
        edited.settings.body.fontFamily = .init(rawValue: "Helvetica Neue")
        edited.settings.headings.fontFamily = .init(rawValue: "Songti SC")
        edited.settings.body.cjkStrongFontFamily = "Noto Sans CJK SC"
        edited.settings.body.cjkEmphasisFontFamily = "Kaiti SC"
        edited.settings.source = .init(fontFamily: "Helvetica Neue", fontSizePoints: 16)
        edited.settings.headings.cjkStrongFontFamily = "Songti SC"
        edited.settings.headings.cjkEmphasisFontFamily = "STKaiti"
        edited.settings.headings.weight = 600
        edited.settings.hyphenation = .automatic
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
        #expect(persistedCopy.settings.body.fontFamily.rawValue == "Helvetica Neue")
        #expect(persistedCopy.settings.headings.fontFamily.rawValue == "Songti SC")
        #expect(persistedCopy.settings.body.cjkStrongFontFamily == "Noto Sans CJK SC")
        #expect(persistedCopy.settings.body.cjkEmphasisFontFamily == "Kaiti SC")
        #expect(persistedCopy.settings.source.fontFamily == "Helvetica Neue")
        #expect(persistedCopy.settings.source.fontSizePoints == 16)
        #expect(persistedCopy.settings.headings.cjkStrongFontFamily == "Songti SC")
        #expect(persistedCopy.settings.headings.cjkEmphasisFontFamily == "STKaiti")
        #expect(persistedCopy.settings.headings.weight == 600)
        #expect(persistedCopy.settings.hyphenation == .automatic)
        #expect(persistedCopy.settings.callout(.orientation).startInsetEm == 4.25)

        let removed = try await reloaded.removeAppearanceProfile(copyID)
        #expect(removed.appearanceProfiles.count == 1)
        #expect(removed.selectedAppearanceProfileID == original.id)
    }

    @Test("Legacy appearance files default missing hyphenation to Never")
    func legacyAppearanceDefaultsHyphenation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumLegacyAppearance-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let setup = StyleOperations(applicationSupportURL: support)
        let initial = try await setup.styleSnapshot()
        let url = try await setup.appearanceConfigurationURL()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        var profiles = try #require(manifest["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        settings.removeValue(forKey: "hyphenation")
        profiles[0]["settings"] = settings
        manifest["profiles"] = profiles
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try legacyBytes.write(to: url, options: .atomic)

        let reloaded = StyleOperations(applicationSupportURL: support)
        let snapshot = try await reloaded.reloadAppearanceConfiguration()
        #expect(snapshot.appearanceProfiles.first?.settings.hyphenation == DocumentHyphenation.none)
        #expect(snapshot.canModifyAppearance)
        #expect(try Data(contentsOf: url) == legacyBytes)
        #expect(initial.appearanceProfiles.first?.settings.hyphenation == DocumentHyphenation.none)
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
            (Double.nan, DocumentAppearanceSettings.defaultLineWidthCharacterUnits),
            (Double.infinity, DocumentAppearanceSettings.defaultLineWidthCharacterUnits),
        ] {
            var candidate = original
            candidate.settings.lineWidthCharacterUnits = input
            let snapshot = try await operations.updateAppearanceProfile(candidate)
            #expect(snapshot.appearanceProfiles.first?.settings.lineWidthCharacterUnits == expected)
        }
    }

    @Test("Incomplete appearance manifests are rejected without rewriting bytes", arguments: ["lineWidthCharacterUnits", "source"])
    func appearanceManifestRequiresCanonicalSettings(missingField: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumAppearanceLineWidthContract-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let styles =
            support
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)

        let profile = DocumentAppearanceProfile(name: "Incomplete")
        let profileData = try JSONEncoder().encode(profile)
        var profileObject = try #require(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        )
        var settings = try #require(profileObject["settings"] as? [String: Any])
        settings.removeValue(forKey: missingField)
        profileObject["settings"] = settings
        let manifest =
            [
                "selectedProfileID": profile.id.uuidString,
                "profiles": [profileObject],
            ] as [String: Any]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try manifestData.write(to: styles.appendingPathComponent("appearances.json"), options: .atomic)

        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let loaded = try await operations.styleSnapshot()
        #expect(loaded.appearanceProfiles.count == 1)
        #expect(loaded.selectedAppearanceProfileID == profile.id)
        #expect(!loaded.canModifyAppearance)
        #expect(loaded.appearanceError != nil)
        #expect(try Data(contentsOf: styles.appendingPathComponent("appearances.json")) == manifestData)
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
    @Test("Appearance defaults preserve the exact damaged configuration in a recovery copy")
    func appearanceRecovery() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/style-recovery-fixtures/\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = StyleOperations(applicationSupportURL: root)
        let appearanceURL = try await operations.appearanceConfigurationURL()
        let corrupt = Data("{broken configuration".utf8)
        try corrupt.write(to: appearanceURL, options: .atomic)
        let reopened = StyleOperations(applicationSupportURL: root)
        let damaged = try await reopened.styleSnapshot()
        #expect(!damaged.canModifyAppearance)
        let recovered = try await reopened.restoreAppearanceDefaults()
        #expect(recovered.canModifyAppearance && recovered.appearanceError == nil)
        let backups = try FileManager.default.contentsOfDirectory(at: appearanceURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("appearances.json.recovery-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: try #require(backups.first)) == corrupt)
    }

    @Test("An invalid appearance option retains other values without rewriting configuration")
    func partialAppearanceRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScholiumAppearanceRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = StyleOperations(applicationSupportURL: root)
        _ = try await setup.styleSnapshot()
        let url = try await setup.appearanceConfigurationURL()
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var profiles = try #require(manifest["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        var body = try #require(settings["body"] as? [String: Any])
        body["alignment"] = "unsupported-version-value"
        body["fontSizePoints"] = 15
        settings["body"] = body
        profiles[0]["settings"] = settings
        manifest["profiles"] = profiles
        let bytes = try JSONSerialization.data(withJSONObject: manifest)
        try bytes.write(to: url, options: .atomic)
        let operations = StyleOperations(applicationSupportURL: root)
        let loaded = try await operations.styleSnapshot()
        let retained = try #require(loaded.appearanceProfiles.first)
        #expect(retained.settings.body.fontSizePoints == 15)
        #expect(retained.settings.body.alignment == .start)
        #expect(!loaded.canModifyAppearance && loaded.appearanceError != nil)
        #expect(try Data(contentsOf: url) == bytes)
        var draft = retained
        draft.settings.body.fontSizePoints = 16
        let repaired = try await operations.repairAppearanceProfile(draft)
        #expect(repaired.canModifyAppearance && repaired.appearanceError == nil)
        #expect(repaired.appearanceProfiles.first?.settings.body.fontSizePoints == 16)
        let backup = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("appearances.json.recovery-") }
        #expect(try Data(contentsOf: try #require(backup)) == bytes)
    }

    @Test("Profile repair preserves unknown keys and sibling profiles and rejects a stale file")
    func appearanceRepairPreservesUnknownState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScholiumAppearanceOverlay-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = StyleOperations(applicationSupportURL: root)
        _ = try await setup.styleSnapshot()
        let url = try await setup.appearanceConfigurationURL()
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var profiles = try #require(manifest["profiles"] as? [[String: Any]])
        var settings = try #require(profiles[0]["settings"] as? [String: Any])
        settings["lineWidthCharacterUnits"] = "bad option"
        settings["unknownSetting"] = ["preserved": true]
        profiles[0]["settings"] = settings
        let sibling: [String: Any] = ["id": UUID().uuidString, "futureProfile": ["exactValue": 23]]
        manifest["profiles"] = profiles + [sibling]
        manifest["futureEnvelope"] = "retained"
        let original = try JSONSerialization.data(withJSONObject: manifest)
        try original.write(to: url, options: .atomic)
        let operations = StyleOperations(applicationSupportURL: root)
        let loaded = try await operations.styleSnapshot()
        var draft = try #require(loaded.appearanceProfiles.first)
        draft.settings.body.fontSizePoints = 16
        let repaired = try await operations.repairAppearanceProfile(draft)
        #expect(!repaired.canModifyAppearance && repaired.appearanceError != nil)
        #expect(repaired.appearanceProfiles.first?.settings.body.fontSizePoints == 16)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let savedProfiles = try #require(saved["profiles"] as? [[String: Any]])
        #expect(saved["futureEnvelope"] as? String == "retained")
        #expect((savedProfiles[1] as NSDictionary).isEqual(to: sibling))
        let savedSettings = try #require(savedProfiles[0]["settings"] as? [String: Any])
        #expect((savedSettings["unknownSetting"] as? [String: Bool])?["preserved"] == true)
        let external = Data("changed elsewhere".utf8)
        try external.write(to: url, options: .atomic)
        await #expect(throws: (any Error).self) { try await operations.repairAppearanceProfile(draft) }
        #expect(try Data(contentsOf: url) == external)
    }

}
