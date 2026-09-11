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
        #expect(original.settings.lineWidthCharacterUnits == 66)
        #expect(original.settings.body.fontSizePoints == 12)
        #expect(original.settings.body.lineHeight == 1.7)

        var edited = original
        edited.settings.lineWidthCharacterUnits = 84
        edited.settings.body.fontSizePoints = 14.5
        edited.settings.body.cjkStrongFontFamily = "Noto Sans CJK SC"
        edited.settings.body.cjkEmphasisFontFamily = "Kaiti SC"
        edited.settings.source = .init(fontFamily: "Helvetica Neue", fontSizePoints: 16)
        edited.settings.headings.cjkStrongFontFamily = "Songti SC"
        edited.settings.headings.cjkEmphasisFontFamily = "STKaiti"
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
        #expect(persistedCopy.settings.body.cjkStrongFontFamily == "Noto Sans CJK SC")
        #expect(persistedCopy.settings.body.cjkEmphasisFontFamily == "Kaiti SC")
        #expect(persistedCopy.settings.source.fontFamily == "Helvetica Neue")
        #expect(persistedCopy.settings.source.fontSizePoints == 16)
        #expect(persistedCopy.settings.headings.cjkStrongFontFamily == "Songti SC")
        #expect(persistedCopy.settings.headings.cjkEmphasisFontFamily == "STKaiti")
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
            (Double.nan, 66.0),
            (Double.infinity, 66.0),
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
        #expect(loaded.appearanceProfiles.isEmpty)
        #expect(loaded.selectedAppearanceProfileID == nil)
        #expect(!loaded.canModify)
        #expect(loaded.storeError != nil)
        #expect(try Data(contentsOf: styles.appendingPathComponent("appearances.json")) == manifestData)
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
        let snippetsFolder = try await operations.managedStylesLocation()
        #expect(snippetsFolder.path.contains("Application Support"))
        #expect(snippetsFolder.lastPathComponent == "Snippets")
    }

    @Test("CSS folder files are discovered, reloaded, and kept visible when invalid or missing")
    func cssFolderDiscoveryAndReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumStyleFolder-(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let snippetsFolder =
            support
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
            .appendingPathComponent("Snippets", isDirectory: true)
        try FileManager.default.createDirectory(at: snippetsFolder, withIntermediateDirectories: true)
        let validURL = snippetsFolder.appendingPathComponent("paper.css")
        let invalidURL = snippetsFolder.appendingPathComponent("broken.css")
        try Data(".callout { background-color: #f4f0e8; }\n".utf8)
            .write(to: validURL, options: .atomic)
        try Data(".not-supported { display: none; }\n".utf8)
            .write(to: invalidURL, options: .atomic)

        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let refreshed = try await operations.refreshStyleSnippets()
        #expect(refreshed.snippets.map(\.name) == ["broken", "paper"])
        #expect(refreshed.snippets.allSatisfy { $0.isEnabled })
        #expect(refreshed.readCSS.contains(".scholium-callout"))
        let broken = try #require(refreshed.snippets.first(where: { $0.name == "broken" }))
        #expect(refreshed.validationErrors[broken.id] != nil)

        try Data(".callout-title { font-style: italic; }\n".utf8)
            .write(to: validURL, options: .atomic)
        let reloaded = try await operations.refreshStyleSnippets()
        let paper = try #require(reloaded.snippets.first(where: { $0.name == "paper" }))
        #expect(reloaded.validationErrors[paper.id] == nil)
        #expect(reloaded.readCSS.contains(".scholium-callout-title"))

        try FileManager.default.removeItem(at: validURL)
        let missing = try await operations.refreshStyleSnippets()
        #expect(missing.snippets.contains(where: { $0.id == paper.id }))
        #expect(missing.validationErrors[paper.id] != nil)
    }

    @Test("CSS snippet names are normalized and never enter generated CSS")
    func cssSnippetNamesStayInert() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumStyleSnippetNames-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hostile = "</style><script id=\"scholium-proof\">0</script><style>"
        let sourceURL = root.appendingPathComponent("Readable.css")
        try Data("p { color: #543210; }\n".utf8).write(to: sourceURL)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)

        let imported = try await operations.importStyleSnippet(from: sourceURL)
        let record = try #require(imported.snippets.first)
        let renamed = try await operations.renameStyleSnippet(record.id, to: hostile)
        let renamedRecord = try #require(renamed.snippets.first)

        #expect(renamedRecord.name == "/stylescript id=\"scholium-proof\"0/scriptstyle")
        #expect(!renamed.readCSS.contains("scholium-proof"))
        #expect(!renamed.readCSS.contains("</style>"))
        #expect(!renamed.livePreviewCSS.contains(hostile))
        #expect(!renamed.readCSS.contains(renamedRecord.name))
        #expect(renamed.readCSS.contains("#543210"))

        let persisted: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let reloaded = try await persisted.styleSnapshot()
        #expect(reloaded.snippets.first?.name == renamedRecord.name)
    }

    @Test("Tampered snippet manifests normalize hostile names on load")
    func tamperedSnippetManifestNamesAreNormalized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumTamperedSnippetManifest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let styles =
            support
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
        let managedFileName = UUID().uuidString.lowercased() + ".css"
        let snippetsDirectory = styles.appendingPathComponent("Snippets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: snippetsDirectory,
            withIntermediateDirectories: true
        )
        try Data("p { color: #543210; }\n".utf8).write(
            to: snippetsDirectory.appendingPathComponent(managedFileName),
            options: .atomic
        )

        let record = CSSSnippetRecord(
            id: UUID(),
            name: "</style><script id=\"scholium-proof\">0</script><style>",
            managedFileName: managedFileName,
            isEnabled: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([record]).write(
            to: styles.appendingPathComponent("snippets.json"),
            options: .atomic
        )

        let operations: any StyleUseCases = StyleOperations(applicationSupportURL: support)
        let loaded = try await operations.styleSnapshot()
        #expect(loaded.snippets.first?.name == "/stylescript id=\"scholium-proof\"0/scriptstyle")
        #expect(!loaded.readCSS.contains("scholium-proof"))
        #expect(!loaded.livePreviewCSS.contains("</style>"))
        #expect(loaded.readCSS.contains("#543210"))
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
