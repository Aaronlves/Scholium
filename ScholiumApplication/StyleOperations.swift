import Foundation
import ScholiumContracts

/// Owns named Appearance profiles and every persisted CSS-snippet byte under
/// Application Support. The frontend receives immutable snapshots and may
/// only present returned URLs.
public actor StyleOperations: StyleUseCases {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let manifestURL: URL
    private let appearanceManifestURL: URL
    private let safeModeURL: URL

    private var appearanceProfiles: [DocumentAppearanceProfile] = []
    private var selectedAppearanceProfileID: UUID?
    private var snippets: [CSSSnippetRecord] = []
    private var validationErrors: [UUID: String] = [:]
    private var readCSS = ""
    private var livePreviewCSS = ""
    private var safeModeReason: String?
    private var storeError: String?
    private var manifestLoadFailure: Error?
    private var didLoad = false
    private var loadedAppearanceBytes: Data?

    public init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL =
            applicationSupportURL
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
            .appendingPathComponent("Snippets", isDirectory: true)
        manifestURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("snippets.json")
        appearanceManifestURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("appearances.json")
        safeModeURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("css-safe-mode.txt")
    }

    public func styleSnapshot() throws -> StyleSnapshot {
        ensureLoaded()
        return snapshot()
    }

    public func appearanceConfigurationURL() throws -> URL {
        ensureLoaded()
        return appearanceManifestURL
    }

    public func reloadAppearanceConfiguration() throws -> StyleSnapshot {
        ensureLoaded()
        let bytes = try readAppearanceBytes()
        let manifest = try decodeAppearance(bytes)
        var recoveredSnippets = snippets
        // A repaired file can also recover a failed first load. Snippet errors
        // are rechecked independently before allowing writes again.
        if manifestLoadFailure != nil {
            if fileManager.fileExists(atPath: manifestURL.path) {
                recoveredSnippets = try JSONDecoder().decode([CSSSnippetRecord].self, from: Data(contentsOf: manifestURL))
                    .map(normalizedSnippetRecord)
            }
        }
        appearanceProfiles = manifest.profiles
        selectedAppearanceProfileID = manifest.selectedProfileID
        loadedAppearanceBytes = bytes
        snippets = recoveredSnippets
        manifestLoadFailure = nil
        rebuildCSS()
        storeError = nil
        return snapshot()
    }

    public func createAppearanceProfile(named requestedName: String) throws -> StyleSnapshot {
        ensureLoaded()
        try requireWritableManifest()
        let name = normalizedName(requestedName, fallback: "Untitled Appearance")
        let profile = DocumentAppearanceProfile(name: name)
        try commitAppearance(appearanceProfiles + [profile], selectedID: profile.id)
        return snapshot()
    }

    public func selectAppearanceProfile(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard appearanceProfiles.contains(where: { $0.id == id }) else { return snapshot() }
        try commitAppearance(appearanceProfiles, selectedID: id)
        return snapshot()
    }

    public func updateAppearanceProfile(_ profile: DocumentAppearanceProfile) throws -> StyleSnapshot {
        ensureLoaded()
        guard let index = appearanceProfiles.firstIndex(where: { $0.id == profile.id }) else {
            return snapshot()
        }
        var candidate = appearanceProfiles
        candidate[index] = normalized(profile)
        try commitAppearance(candidate, selectedID: selectedAppearanceProfileID)
        return snapshot()
    }

    public func renameAppearanceProfile(_ id: UUID, to requestedName: String) throws -> StyleSnapshot {
        ensureLoaded()
        let name = normalizedName(requestedName, fallback: "")
        guard !name.isEmpty,
            let index = appearanceProfiles.firstIndex(where: { $0.id == id })
        else {
            return snapshot()
        }
        var candidate = appearanceProfiles
        candidate[index].name = name
        try commitAppearance(candidate, selectedID: selectedAppearanceProfileID)
        return snapshot()
    }

    public func duplicateAppearanceProfile(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard let source = appearanceProfiles.first(where: { $0.id == id }) else {
            return snapshot()
        }
        let copy = DocumentAppearanceProfile(
            name: source.name + " Copy",
            settings: source.settings
        )
        try commitAppearance(appearanceProfiles + [copy], selectedID: copy.id)
        return snapshot()
    }

    public func removeAppearanceProfile(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard appearanceProfiles.count > 1,
            appearanceProfiles.contains(where: { $0.id == id })
        else {
            return snapshot()
        }
        let candidate = appearanceProfiles.filter { $0.id != id }
        let nextSelectedID =
            selectedAppearanceProfileID == id
            ? candidate.first?.id
            : selectedAppearanceProfileID
        try commitAppearance(candidate, selectedID: nextSelectedID)
        return snapshot()
    }

    public func importStyleSnippet(from sourceURL: URL) throws -> StyleSnapshot {
        ensureLoaded()
        try requireWritableManifest()
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        guard data.count <= CSSSnippetSanitizer.maximumUTF8Size else {
            throw CSSSnippetSanitizationError.tooLarge
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        _ = try CSSSnippetSanitizer.sanitize(source)

        try ensureDirectory()
        let id = UUID()
        let managedFileName = id.uuidString.lowercased() + ".css"
        let destination = directoryURL.appendingPathComponent(managedFileName)
        try data.write(to: destination, options: [.atomic])
        let displayName = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CSSSnippetRecord(
            id: id,
            name: CSSSnippetSanitizer.normalizedSnippetName(
                displayName,
                fallback: "CSS Snippet"
            ),
            managedFileName: managedFileName,
            isEnabled: true,
            sourceFingerprint: DocumentFingerprint(content: source).sha256
        )
        do {
            try commit(snippets + [record], clearingSafeMode: true)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return snapshot()
    }

    public func refreshStyleSnippets() throws -> StyleSnapshot {
        ensureLoaded()
        try requireWritableManifest()
        try ensureDirectory()
        // The folder is the source of truth for snippet bytes. The manifest
        // only retains stable identity, ordering, enablement, and the display
        // name, so a researcher can add a plain .css file without importing it
        // through the app first.
        try commit(reconciledSnippetRecords(), clearingSafeMode: false)
        return snapshot()
    }

    public func setStyleSnippetEnabled(_ enabled: Bool, id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        try mutate { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == id }) else { return false }
            candidate[index].isEnabled = enabled
            return true
        }
        return snapshot()
    }

    public func moveStyleSnippet(_ id: UUID, by offset: Int) throws -> StyleSnapshot {
        ensureLoaded()
        try mutate { candidate in
            guard let source = candidate.firstIndex(where: { $0.id == id }) else { return false }
            let destination = source + offset
            guard candidate.indices.contains(destination) else { return false }
            let record = candidate.remove(at: source)
            candidate.insert(record, at: destination)
            return true
        }
        return snapshot()
    }

    public func renameStyleSnippet(_ id: UUID, to requestedName: String) throws -> StyleSnapshot {
        ensureLoaded()
        let name = CSSSnippetSanitizer.normalizedSnippetName(requestedName, fallback: "")
        guard !name.isEmpty else { return snapshot() }
        try mutate { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == id }) else { return false }
            candidate[index].name = name
            return true
        }
        return snapshot()
    }

    public func duplicateStyleSnippet(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard let source = snippets.first(where: { $0.id == id }) else { return snapshot() }
        try requireWritableManifest()
        let sourceURL = try managedURL(for: source)
        let data = try Data(contentsOf: sourceURL)
        let copyID = UUID()
        let fileName = copyID.uuidString.lowercased() + ".css"
        let target = directoryURL.appendingPathComponent(fileName)
        try data.write(to: target, options: .atomic)
        let copy = CSSSnippetRecord(
            id: copyID,
            name: CSSSnippetSanitizer.normalizedSnippetName(
                source.name + " Copy",
                fallback: source.name + " Copy"
            ),
            managedFileName: fileName,
            isEnabled: source.isEnabled,
            sourceFingerprint: source.sourceFingerprint
        )
        do {
            try commit(snippets + [copy], clearingSafeMode: true)
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }
        return snapshot()
    }

    public func reloadStyleSnippet(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard snippets.contains(where: { $0.id == id }) else { return snapshot() }
        try requireWritableManifest()
        try commit(snippets, clearingSafeMode: false)
        return snapshot()
    }

    public func removeStyleSnippet(_ id: UUID) throws -> StyleSnapshot {
        ensureLoaded()
        guard let record = snippets.first(where: { $0.id == id }) else { return snapshot() }
        try requireWritableManifest()
        try commit(snippets.filter { $0.id != id }, clearingSafeMode: true)
        try? fileManager.removeItem(at: managedURL(for: record))
        return snapshot()
    }

    public func disableAllStyleSnippets() throws -> StyleSnapshot {
        ensureLoaded()
        try mutate { candidate in
            for index in candidate.indices { candidate[index].isEnabled = false }
            return true
        }
        return snapshot()
    }

    public func enterStyleSafeMode(reason: String) throws -> StyleSnapshot {
        ensureLoaded()
        guard snippets.contains(where: \.isEnabled), manifestLoadFailure == nil else {
            return snapshot()
        }
        var candidate = snippets
        for index in candidate.indices { candidate[index].isEnabled = false }
        do {
            try commit(candidate, clearingSafeMode: false)
            try Data(reason.utf8).write(to: safeModeURL, options: .atomic)
            safeModeReason = reason
        } catch {
            readCSS = ""
            livePreviewCSS = ""
            safeModeReason = reason
            storeError = "Scholium could not enter CSS Safe Mode: \(error.localizedDescription)"
            throw error
        }
        return snapshot()
    }

    public func managedStyleSnippetURL(_ id: UUID) throws -> URL? {
        ensureLoaded()
        guard let record = snippets.first(where: { $0.id == id }) else { return nil }
        return try managedURL(for: record)
    }

    public func managedStylesLocation() throws -> URL {
        ensureLoaded()
        try ensureDirectory()
        return directoryURL
    }

    public func obsidianAppearance(at vaultRootURL: URL) -> ObsidianAppearanceSnapshot? {
        let obsidianURL = vaultRootURL.appendingPathComponent(".obsidian", isDirectory: true)
        guard fileManager.fileExists(atPath: obsidianURL.path) else { return nil }
        var theme: String?
        var showLineNumbers: Bool?
        var defaultViewMode: String?
        var attachmentFolderPath: String?
        var newLinkFormat: String?
        var vaultName: String?
        if let object = jsonObject(at: obsidianURL.appendingPathComponent("app.json")) {
            theme = object["theme"] as? String
            showLineNumbers = object["showLineNumber"] as? Bool
            defaultViewMode = object["defaultViewMode"] as? String
            attachmentFolderPath = object["attachmentFolderPath"] as? String
            newLinkFormat = object["newLinkFormat"] as? String
        }
        if theme == nil,
            let object = jsonObject(at: obsidianURL.appendingPathComponent("appearance.json"))
        {
            theme = object["theme"] as? String
        }
        if let object = jsonObject(at: obsidianURL.appendingPathComponent("core-plugins.json")) {
            vaultName = object["vaultName"] as? String
        }
        return ObsidianAppearanceSnapshot(
            vaultName: vaultName,
            theme: theme,
            showLineNumbers: showLineNumbers,
            defaultViewMode: defaultViewMode,
            attachmentFolderPath: attachmentFolderPath,
            newLinkFormat: newLinkFormat
        )
    }

    private func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        do {
            try ensureDirectory()
            if fileManager.fileExists(atPath: manifestURL.path) {
                snippets = try JSONDecoder()
                    .decode([CSSSnippetRecord].self, from: Data(contentsOf: manifestURL))
                    .map(normalizedSnippetRecord)
            }
            if fileManager.fileExists(atPath: appearanceManifestURL.path) {
                let bytes = try readAppearanceBytes()
                let manifest = try decodeAppearance(bytes)
                loadedAppearanceBytes = bytes
                appearanceProfiles = manifest.profiles
                selectedAppearanceProfileID = manifest.selectedProfileID
            } else {
                let profile = DocumentAppearanceProfile(name: "Custom")
                appearanceProfiles = [profile]
                selectedAppearanceProfileID = profile.id
                try writeAppearanceManifest(
                    AppearanceManifest(selectedProfileID: profile.id, profiles: [profile])
                )
            }
            if appearanceProfiles.isEmpty {
                let profile = DocumentAppearanceProfile(name: "Custom")
                appearanceProfiles = [profile]
                selectedAppearanceProfileID = profile.id
            } else if !appearanceProfiles.contains(where: { $0.id == selectedAppearanceProfileID }) {
                selectedAppearanceProfileID = appearanceProfiles.first?.id
            }
            if fileManager.fileExists(atPath: safeModeURL.path),
                let persisted = String(data: try Data(contentsOf: safeModeURL), encoding: .utf8),
                !persisted.isEmpty
            {
                safeModeReason = persisted
                for index in snippets.indices { snippets[index].isEnabled = false }
            }
            rebuildCSS()
        } catch {
            manifestLoadFailure = error
            snippets = []
            appearanceProfiles = []
            selectedAppearanceProfileID = nil
            validationErrors = [:]
            readCSS = ""
            livePreviewCSS = ""
            storeError = StyleUseCaseError.unavailable(error.localizedDescription).localizedDescription
            safeModeReason = "Scholium disabled document CSS because its snippet settings could not be read."
        }
    }

    private func snapshot() -> StyleSnapshot {
        StyleSnapshot(
            appearanceProfiles: appearanceProfiles,
            selectedAppearanceProfileID: selectedAppearanceProfileID,
            snippets: snippets,
            validationErrors: validationErrors,
            readCSS: readCSS,
            livePreviewCSS: livePreviewCSS,
            safeModeReason: safeModeReason,
            storeError: storeError,
            canModify: manifestLoadFailure == nil
        )
    }

    private func requireWritableManifest() throws {
        if let manifestLoadFailure {
            throw StyleUseCaseError.unavailable(manifestLoadFailure.localizedDescription)
        }
    }

    private func mutate(_ change: (inout [CSSSnippetRecord]) -> Bool) throws {
        try requireWritableManifest()
        var candidate = snippets
        guard change(&candidate) else { return }
        try commit(candidate, clearingSafeMode: true)
    }

    private func commit(_ candidate: [CSSSnippetRecord], clearingSafeMode: Bool) throws {
        try requireWritableManifest()
        try ensureDirectory()
        let build = buildCSS(from: candidate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(build.snippets).write(to: manifestURL, options: [.atomic])
        if clearingSafeMode { try? fileManager.removeItem(at: safeModeURL) }
        snippets = build.snippets
        validationErrors = build.errors
        readCSS = build.readCSS
        livePreviewCSS = build.livePreviewCSS
        if clearingSafeMode { safeModeReason = nil }
        storeError = nil
    }

    private struct AppearanceManifest: Codable {
        var selectedProfileID: UUID
        var profiles: [DocumentAppearanceProfile]
    }

    private func commitAppearance(
        _ profiles: [DocumentAppearanceProfile],
        selectedID: UUID?
    ) throws {
        try requireWritableManifest()
        try ensureDirectory()
        let normalizedProfiles = profiles.map(normalized)
        guard let firstID = normalizedProfiles.first?.id else { return }
        let resolvedSelectedID: UUID
        if let selectedID,
            normalizedProfiles.contains(where: { $0.id == selectedID })
        {
            resolvedSelectedID = selectedID
        } else {
            resolvedSelectedID = firstID
        }
        try writeAppearanceManifest(
            AppearanceManifest(
                selectedProfileID: resolvedSelectedID,
                profiles: normalizedProfiles
            )
        )
        appearanceProfiles = normalizedProfiles
        selectedAppearanceProfileID = resolvedSelectedID
        storeError = nil
    }

    private func writeAppearanceManifest(_ manifest: AppearanceManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(manifest)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: appearanceManifestURL, options: .forReplacing, error: &coordinationError) { url in
            do {
                let current = fileManager.fileExists(atPath: url.path) ? try readAppearanceBytes() : nil
                guard current == loadedAppearanceBytes else { throw StyleUseCaseError.configurationChanged }
                try bytes.write(to: url, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        loadedAppearanceBytes = bytes
    }

    private func readAppearanceBytes() throws -> Data {
        let values = try appearanceManifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            (values.fileSize ?? 0) <= 2_000_000
        else {
            throw StyleUseCaseError.invalidConfiguration("appearances.json must be a regular file smaller than 2 MB.")
        }
        let bytes = try Data(contentsOf: appearanceManifestURL)
        guard bytes.count <= 2_000_000 else {
            throw StyleUseCaseError.invalidConfiguration("appearances.json must be smaller than 2 MB.")
        }
        return bytes
    }

    private func decodeAppearance(_ bytes: Data) throws -> AppearanceManifest {
        do {
            let manifest = try JSONDecoder().decode(AppearanceManifest.self, from: bytes)
            guard !manifest.profiles.isEmpty,
                Set(manifest.profiles.map(\.id)).count == manifest.profiles.count,
                manifest.profiles.contains(where: { $0.id == manifest.selectedProfileID })
            else {
                throw StyleUseCaseError.invalidConfiguration("profiles must have unique IDs and contain selectedProfileID.")
            }
            let normalizedManifest = AppearanceManifest(
                selectedProfileID: manifest.selectedProfileID,
                profiles: manifest.profiles.map(normalized)
            )
            let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))
            try rejectUnknownConfigurationKeys(try JSONSerialization.jsonObject(with: bytes), decoded: original, path: "$")
            let normalizedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(normalizedManifest))
            if let path = firstConfigurationDifference(original, normalizedObject, path: "$") {
                throw StyleUseCaseError.invalidConfiguration("\(path) is outside its supported range or has an invalid value.")
            }
            return manifest
        } catch let error as DecodingError {
            let context: DecodingError.Context
            var missingKey: String?
            switch error {
            case .keyNotFound(let key, let value):
                context = value
                missingKey = key.stringValue
            case .typeMismatch(_, let value), .valueNotFound(_, let value), .dataCorrupted(let value): context = value
            @unknown default: throw StyleUseCaseError.invalidConfiguration(error.localizedDescription)
            }
            let components = context.codingPath.map { $0.stringValue } + (missingKey.map { [$0] } ?? [])
            throw StyleUseCaseError.invalidConfiguration("\((components.isEmpty ? ["$"] : components).joined(separator: ".")): \(context.debugDescription)")
        }
    }

    private func firstConfigurationDifference(_ original: Any, _ normalized: Any, path: String) -> String? {
        if let lhs = original as? [String: Any], let rhs = normalized as? [String: Any] {
            for key in Set(lhs.keys).union(rhs.keys).sorted() {
                guard let a = lhs[key], let b = rhs[key] else { return "\(path).\(key)" }
                if let changed = firstConfigurationDifference(a, b, path: "\(path).\(key)") { return changed }
            }
            return nil
        }
        if let lhs = original as? [Any], let rhs = normalized as? [Any] {
            guard lhs.count == rhs.count else { return path }
            for index in lhs.indices {
                if let changed = firstConfigurationDifference(lhs[index], rhs[index], path: "\(path)[\(index)]") { return changed }
            }
            return nil
        }
        return (original as? NSObject)?.isEqual(normalized) == true ? nil : path
    }

    private func rejectUnknownConfigurationKeys(_ input: Any, decoded: Any, path: String) throws {
        if let input = input as? [String: Any], let decoded = decoded as? [String: Any] {
            let optionalCalloutKeys: Set<String> = [
                "lineHeight", "startInsetEm", "endInsetEm", "titleGapEm", "paddingBlockEm", "paddingInlineEm",
                "contentIndentEm", "quotationScale", "attributionScale",
            ]
            for (key, value) in input {
                guard let canonical = decoded[key] else {
                    if decoded["role"] != nil, optionalCalloutKeys.contains(key), value is NSNull { continue }
                    throw StyleUseCaseError.invalidConfiguration("\(path).\(key) is not a supported field.")
                }
                try rejectUnknownConfigurationKeys(value, decoded: canonical, path: "\(path).\(key)")
            }
        } else if let input = input as? [Any], let decoded = decoded as? [Any] {
            for (index, pair) in zip(input, decoded).enumerated() {
                try rejectUnknownConfigurationKeys(pair.0, decoded: pair.1, path: "\(path)[\(index)]")
            }
        }
    }

    private func normalized(_ profile: DocumentAppearanceProfile) -> DocumentAppearanceProfile {
        var profile = profile
        profile.name = normalizedName(profile.name, fallback: "Untitled Appearance")
        profile.settings.lineWidthCharacterUnits =
            profile.settings.lineWidthCharacterUnits.isFinite
            ? profile.settings.lineWidthCharacterUnits.clamped(
                to: DocumentAppearanceSettings.lineWidthCharacterUnitsRange
            )
            : DocumentAppearanceSettings.defaultLineWidthCharacterUnits
        profile.settings.body.fontSizePoints = profile.settings.body.fontSizePoints.clamped(to: 9...24)
        profile.settings.source.fontSizePoints =
            profile.settings.source.fontSizePoints.isFinite
            ? profile.settings.source.fontSizePoints.clamped(to: 6...72)
            : DocumentSourceAppearance().fontSizePoints
        profile.settings.body.lineHeight = profile.settings.body.lineHeight.clamped(to: 1.2...2.4)
        profile.settings.body.paragraphSpacingEm = profile.settings.body.paragraphSpacingEm.clamped(to: 0...2)
        profile.settings.body.firstLineIndentEm = profile.settings.body.firstLineIndentEm.clamped(to: 0...4)
        profile.settings.headings.weight = profile.settings.headings.weight.clamped(to: 400...700)
        profile.settings.headings.lineHeight = profile.settings.headings.lineHeight.clamped(to: 1...2.4)
        profile.settings.headings.level1 = normalized(profile.settings.headings.level1)
        profile.settings.headings.level2 = normalized(profile.settings.headings.level2)
        profile.settings.headings.level3 = normalized(profile.settings.headings.level3)
        profile.settings.headings.level4 = normalized(profile.settings.headings.level4)
        profile.settings.headings.level5 = normalized(profile.settings.headings.level5)
        profile.settings.headings.level6 = normalized(profile.settings.headings.level6)
        profile.settings.callouts = DocumentCalloutAppearanceRole.allCases.map { role in
            normalized(profile.settings.callout(role))
        }
        return profile
    }

    private func normalized(
        _ level: DocumentHeadingLevelAppearance
    ) -> DocumentHeadingLevelAppearance {
        var level = level
        level.scale = level.scale.clamped(to: 0.8...3)
        level.spaceBeforeEm = level.spaceBeforeEm.clamped(to: 0...4)
        level.spaceAfterEm = level.spaceAfterEm.clamped(to: 0...4)
        return level
    }

    private func normalized(_ callout: DocumentCalloutAppearance) -> DocumentCalloutAppearance {
        var callout = callout
        callout.inlineInsetEm = callout.inlineInsetEm.clamped(to: 0...4)
        callout.blockGapEm = callout.blockGapEm.clamped(to: 0...4)
        callout.fontScale = callout.fontScale.clamped(to: 0.8...1.4)
        callout.paragraphSpacingEm = callout.paragraphSpacingEm.clamped(to: 0...2)
        callout.titleWeight = callout.titleWeight.clamped(to: 400...700)
        callout.lineHeight = callout.lineHeight?.clamped(to: 1.1...2.4)
        callout.startInsetEm = callout.startInsetEm?.clamped(to: 0...6)
        callout.endInsetEm = callout.endInsetEm?.clamped(to: 0...6)
        callout.titleGapEm = callout.titleGapEm?.clamped(to: 0...2)
        callout.paddingBlockEm = callout.paddingBlockEm?.clamped(to: 0...3)
        callout.paddingInlineEm = callout.paddingInlineEm?.clamped(to: 0...4)
        callout.contentIndentEm = callout.contentIndentEm?.clamped(to: 0...4)
        callout.quotationScale = callout.quotationScale?.clamped(to: 0.8...1.5)
        callout.attributionScale = callout.attributionScale?.clamped(to: 0.6...1.2)
        return callout
    }

    private func normalizedName(_ requestedName: String, fallback: String) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(120))
    }

    private func rebuildCSS() {
        let build = buildCSS(from: snippets)
        snippets = build.snippets
        validationErrors = build.errors
        readCSS = build.readCSS
        livePreviewCSS = build.livePreviewCSS
    }

    private func reconciledSnippetRecords() throws -> [CSSSnippetRecord] {
        let discovered = try discoveredSnippetURLs()
        var records = snippets
        let knownFileNames = Set(records.map(\.managedFileName))
        for url in discovered where !knownFileNames.contains(url.lastPathComponent) {
            let baseName = url.deletingPathExtension().lastPathComponent
            records.append(
                CSSSnippetRecord(
                    id: UUID(),
                    name: CSSSnippetSanitizer.normalizedSnippetName(
                        baseName,
                        fallback: "CSS Snippet"
                    ),
                    managedFileName: url.lastPathComponent,
                    isEnabled: safeModeReason == nil
                ))
        }
        return records
    }

    private func discoveredSnippetURLs() throws -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .nameKey,
        ]
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.caseInsensitiveCompare("css") == .orderedSame,
                url.deletingLastPathComponent().standardizedFileURL
                    == directoryURL.standardizedFileURL
            else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            urls.append(url)
        }
        return urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private struct CSSBuildResult {
        let snippets: [CSSSnippetRecord]
        let errors: [UUID: String]
        let readCSS: String
        let livePreviewCSS: String
    }

    private func buildCSS(from sourceRecords: [CSSSnippetRecord]) -> CSSBuildResult {
        var records = sourceRecords
        var read: [String] = []
        var live: [String] = []
        var errors: [UUID: String] = [:]
        for index in records.indices {
            let snippet = records[index]
            do {
                let data = try Data(contentsOf: managedURL(for: snippet), options: [.mappedIfSafe])
                guard data.count <= CSSSnippetSanitizer.maximumUTF8Size else {
                    throw CSSSnippetSanitizationError.tooLarge
                }
                guard let source = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                let projection = try CSSSnippetSanitizer.sanitize(source)
                records[index].sourceFingerprint = DocumentFingerprint(content: source).sha256
                records[index].lastFailure = nil
                if records[index].isEnabled {
                    read.append("/* Scholium user CSS snippet */\n\(projection.readCSS)")
                    live.append("/* Scholium user CSS snippet */\n\(projection.livePreviewCSS)")
                }
            } catch {
                errors[snippet.id] = error.localizedDescription
                records[index].lastFailure = error.localizedDescription
            }
        }
        return CSSBuildResult(
            snippets: records,
            errors: errors,
            readCSS: read.joined(separator: "\n\n"),
            livePreviewCSS: live.joined(separator: "\n\n")
        )
    }

    private func normalizedSnippetRecord(
        _ record: CSSSnippetRecord
    ) -> CSSSnippetRecord {
        var record = record
        record.name = CSSSnippetSanitizer.normalizedSnippetName(
            record.name,
            fallback: "CSS Snippet"
        )
        return record
    }

    private func managedURL(for record: CSSSnippetRecord) throws -> URL {
        let url = directoryURL.appendingPathComponent(record.managedFileName).standardizedFileURL
        guard url.deletingLastPathComponent() == directoryURL.standardizedFileURL else {
            throw CSSSnippetSanitizationError.forbiddenConstruct("managed path escape")
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
            values.isSymbolicLink == true
        {
            throw CSSSnippetSanitizationError.forbiddenConstruct("symbolic-link snippet")
        }
        return url
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
