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
        #expect(loaded.appearanceProfiles.count == 1)
        #expect(loaded.selectedAppearanceProfileID == profile.id)
        #expect(!loaded.canModifyAppearance)
        #expect(loaded.canModify)
        #expect(loaded.appearanceError != nil)
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
    @Test("Appearance and snippet failures recover independently with exact backups", arguments: ["appearances.json", "snippets.json"])
    func independentRecovery(_ brokenFile: String) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/style-recovery-fixtures/\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let source = root.appendingPathComponent("kept.css")
        let css = Data("p { color: #543210; }".utf8)
        try css.write(to: source)
        let setup = StyleOperations(applicationSupportURL: support)
        let original = try await setup.importStyleSnippet(from: source)
        let appearanceURL = try await setup.appearanceConfigurationURL()
        let styles = appearanceURL.deletingLastPathComponent()
        let target = styles.appendingPathComponent(brokenFile)
        let corrupt = Data("{broken configuration".utf8)
        try corrupt.write(to: target, options: .atomic)
        let operations = StyleOperations(applicationSupportURL: support)
        let damaged = try await operations.styleSnapshot()
        if brokenFile == "appearances.json" {
            #expect(!damaged.canModifyAppearance && damaged.canModify)
            #expect(damaged.readCSS.contains("#543210"))
            let recovered = try await operations.restoreAppearanceDefaults()
            #expect(recovered.canModifyAppearance && recovered.appearanceError == nil)
            #expect(recovered.snippets == damaged.snippets)
        } else {
            #expect(damaged.canModifyAppearance && !damaged.canModify)
            #expect(damaged.appearanceProfiles == original.appearanceProfiles)
            let recovered = try await operations.restoreStyleSnippetDefaults()
            #expect(recovered.canModify && recovered.snippetError == nil)
            #expect(recovered.snippets.count == 1 && recovered.snippets.allSatisfy { !$0.isEnabled })
            #expect(recovered.appearanceProfiles == original.appearanceProfiles)
            let refreshed = try await operations.refreshStyleSnippets()
            #expect(refreshed.snippets.allSatisfy { !$0.isEnabled } && refreshed.readCSS.isEmpty)
        }
        let backups = try FileManager.default.contentsOfDirectory(at: styles, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(brokenFile).recovery-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: try #require(backups.first)) == corrupt)
        let managed = styles.appendingPathComponent("Snippets", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: managed, includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: try #require(files.first)) == css)
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

    @Test("One malformed snippet registration preserves readable snippets and can be repaired")
    func partialSnippetRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScholiumSnippetRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let source = root.appendingPathComponent("kept.css")
        try Data("p { color: #543210; }".utf8).write(to: source)
        let setup = StyleOperations(applicationSupportURL: support)
        let original = try await setup.importStyleSnippet(from: source)
        let appearance = try await setup.appearanceConfigurationURL()
        let target = appearance.deletingLastPathComponent().appendingPathComponent("snippets.json")
        let validBytes = try Data(contentsOf: target)
        let records = try #require(JSONSerialization.jsonObject(with: validBytes) as? [Any])
        let corrupt = try JSONSerialization.data(withJSONObject: records + [["id": "bad", "name": false]])
        try corrupt.write(to: target, options: .atomic)
        let operations = StyleOperations(applicationSupportURL: support)
        let damaged = try await operations.styleSnapshot()
        #expect(damaged.snippets == original.snippets)
        #expect(damaged.readCSS.contains("#543210") && !damaged.canModify)
        #expect(damaged.canModifyAppearance && damaged.snippetError != nil)
        #expect(try Data(contentsOf: target) == corrupt)
        let safe = try await operations.enterStyleSafeMode(reason: "fixture rendering failure")
        #expect(safe.readCSS.isEmpty && safe.safeModeReason == "fixture rendering failure")
        #expect(try Data(contentsOf: target) == corrupt)
        try validBytes.write(to: target, options: .atomic)
        let repaired = try await operations.refreshStyleSnippets()
        #expect(repaired.canModify && repaired.snippetError == nil)
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
