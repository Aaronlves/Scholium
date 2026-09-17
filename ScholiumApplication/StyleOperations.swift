import Foundation
import ScholiumContracts
import ScholiumCore

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
    private var appearanceLoadFailure: Error?
    private var loadedSnippetBytes: Data?
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
        do {
            let bytes = try readAppearanceBytes()
            loadedAppearanceBytes = bytes
            let manifest = try decodeAppearance(bytes)
            appearanceProfiles = manifest.profiles
            selectedAppearanceProfileID = manifest.selectedProfileID
            loadedAppearanceBytes = bytes
            appearanceLoadFailure = nil
            return snapshot()
        } catch {
            appearanceLoadFailure = error
            throw error
        }
    }

    public func createAppearanceProfile(named requestedName: String) throws -> StyleSnapshot {
        ensureLoaded()
        try requireWritableAppearance()
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
        do { try loadSnippetManifest() } catch {
            manifestLoadFailure = error
            rebuildCSS()
            throw error
        }
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
        guard snippets.contains(where: \.isEnabled) else { return snapshot() }
        var candidate = snippets
        for index in candidate.indices { candidate[index].isEnabled = false }
        do {
            if manifestLoadFailure == nil {
                try commit(candidate, clearingSafeMode: false)
            }
            let existing = fileManager.fileExists(atPath: safeModeURL.path) ? try readRecoveryBytes(at: safeModeURL) : nil
            try coordinatedReplace(at: safeModeURL, bytes: Data(reason.utf8), expected: existing)
            snippets = candidate
            safeModeReason = reason
            rebuildCSS()
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
            try loadSnippetManifest()
        } catch {
            manifestLoadFailure = error
        }
        do {
            if fileManager.fileExists(atPath: appearanceManifestURL.path) {
                let bytes = try readAppearanceBytes()
                loadedAppearanceBytes = bytes
                do {
                    let manifest = try decodeAppearance(bytes)
                    appearanceProfiles = manifest.profiles
                    selectedAppearanceProfileID = manifest.selectedProfileID
                } catch {
                    appearanceLoadFailure = error
                    // Derive a usable projection, preserving readable fields.
                    // The original bytes stay untouched and cannot be written
                    // through this projection until explicit recovery/reload.
                    if let recovered = recoverAppearance(bytes) {
                        appearanceProfiles = recovered.profiles
                        selectedAppearanceProfileID = recovered.selectedProfileID
                    }
                }
            } else {
                let profile = DocumentAppearanceProfile(name: "Custom")
                try writeAppearanceManifest(AppearanceManifest(selectedProfileID: profile.id, profiles: [profile]))
                appearanceProfiles = [profile]
                selectedAppearanceProfileID = profile.id
            }
        } catch {
            appearanceLoadFailure = error
        }
        if let persisted = try? String(contentsOf: safeModeURL, encoding: .utf8), !persisted.isEmpty {
            safeModeReason = persisted
            for index in snippets.indices { snippets[index].isEnabled = false }
        }
        rebuildCSS()
    }

    private func loadSnippetManifest() throws {
        let bytes = fileManager.fileExists(atPath: manifestURL.path) ? try readManifestBytes(at: manifestURL) : nil
        loadedSnippetBytes = bytes
        guard let bytes else {
            snippets = []
            manifestLoadFailure = nil
            return
        }
        guard let objects = try JSONSerialization.jsonObject(with: bytes) as? [Any], objects.count <= 1_000 else {
            throw StyleUseCaseError.invalidConfiguration("CSS snippet settings must be an array of up to 1,000 registrations.")
        }
        var candidate: [CSSSnippetRecord] = []
        var invalidCount = 0
        for object in objects {
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed),
                let record = try? JSONDecoder().decode(CSSSnippetRecord.self, from: data),
                !candidate.contains(where: { $0.id == record.id || $0.managedFileName == record.managedFileName })
            else {
                invalidCount += 1
                continue
            }
            candidate.append(normalizedSnippetRecord(record))
        }
        snippets = candidate
        if safeModeReason != nil {
            for index in snippets.indices { snippets[index].isEnabled = false }
        }
        if invalidCount > 0 {
            throw StyleUseCaseError.invalidConfiguration(
                "\(invalidCount) CSS snippet registration(s) could not be loaded. Readable snippets remain available; repair or restore their settings before saving."
            )
        }
        manifestLoadFailure = nil
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
            canModify: manifestLoadFailure == nil,
            canModifyAppearance: appearanceLoadFailure == nil,
            appearanceError: appearanceLoadFailure?.localizedDescription,
            snippetError: manifestLoadFailure?.localizedDescription
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
        let bytes = try encoder.encode(build.snippets)
        try coordinatedReplace(at: manifestURL, bytes: bytes, expected: loadedSnippetBytes)
        loadedSnippetBytes = bytes
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
        try requireWritableAppearance()
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
        try coordinatedReplace(at: appearanceManifestURL, bytes: bytes, expected: loadedAppearanceBytes)
        loadedAppearanceBytes = bytes
    }

    private func readAppearanceBytes() throws -> Data {
        try readManifestBytes(at: appearanceManifestURL)
    }

    private func readManifestBytes(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            (values.fileSize ?? 0) <= 2_000_000
        else { throw StyleUseCaseError.invalidConfiguration("\(url.lastPathComponent) must be a regular file smaller than 2 MB.") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2_000_000 else {
            throw StyleUseCaseError.invalidConfiguration("\(url.lastPathComponent) must be smaller than 2 MB.")
        }
        return bytes
    }

    private func readRecoveryBytes(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw StyleUseCaseError.invalidConfiguration("\(url.lastPathComponent) must be a regular file.")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func requireWritableAppearance() throws {
        if let appearanceLoadFailure { throw StyleUseCaseError.unavailable(appearanceLoadFailure.localizedDescription) }
    }

    /// Recovery backs up the exact current bytes before replacing only this group.
    /// Failed backup or replacement leaves the live configuration unchanged.
    private func coordinatedReplace(at target: URL, bytes: Data, expected: Data?, preservingOriginal: Bool = false) throws {
        do {
            _ = try ExactFileReplacement.replace(at: target, expected: expected, candidate: bytes, preserveOriginal: preservingOriginal)
        } catch ExactFileReplacementError.revisionConflict {
            throw StyleUseCaseError.configurationChanged
        }
    }

    public func restoreAppearanceDefaults() throws -> StyleSnapshot {
        ensureLoaded()
        try ensureDirectory()
        let current = fileManager.fileExists(atPath: appearanceManifestURL.path) ? try readRecoveryBytes(at: appearanceManifestURL) : nil
        let profile = DocumentAppearanceProfile(name: "Custom")
        let bytes = try JSONEncoder().encode(AppearanceManifest(selectedProfileID: profile.id, profiles: [profile]))
        try coordinatedReplace(at: appearanceManifestURL, bytes: bytes, expected: current, preservingOriginal: true)
        loadedAppearanceBytes = bytes
        appearanceProfiles = [profile]
        selectedAppearanceProfileID = profile.id
        appearanceLoadFailure = nil
        storeError = nil
        return snapshot()
    }

    public func repairAppearanceProfile(_ profile: DocumentAppearanceProfile) throws -> StyleSnapshot {
        ensureLoaded()
        guard appearanceLoadFailure != nil, appearanceProfiles.contains(where: { $0.id == profile.id }),
            let original = loadedAppearanceBytes,
            var root = try JSONSerialization.jsonObject(with: original) as? [String: Any],
            var objects = root["profiles"] as? [Any],
            let index = objects.firstIndex(where: {
                (($0 as? [String: Any])?["id"] as? String).flatMap(UUID.init(uuidString:)) == profile.id
            })
        else { throw StyleUseCaseError.invalidConfiguration("This appearance profile cannot be repaired from its saved configuration.") }
        let repairedProfile = normalized(profile)
        let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(repairedProfile))
        objects[index] = overlayConfiguration(objects[index], known: known)
        root["profiles"] = objects
        root["selectedProfileID"] = profile.id.uuidString
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try coordinatedReplace(at: appearanceManifestURL, bytes: bytes, expected: original, preservingOriginal: true)
        loadedAppearanceBytes = bytes
        do {
            let manifest = try decodeAppearance(bytes)
            appearanceProfiles = manifest.profiles
            selectedAppearanceProfileID = manifest.selectedProfileID
            appearanceLoadFailure = nil
        } catch {
            appearanceLoadFailure = error
            if let recovered = recoverAppearance(bytes) {
                appearanceProfiles = recovered.profiles
                selectedAppearanceProfileID = recovered.selectedProfileID
            }
        }
        storeError = nil
        return snapshot()
    }

    /// Overlay only known profile values. Unknown keys and unrecognized array
    /// members retain their original value and remain nonauthorizing.
    private nonisolated func overlayConfiguration(_ original: Any, known: Any) -> Any {
        if var object = original as? [String: Any], let values = known as? [String: Any] {
            let optionalKeys: [String]
            if values["role"] != nil {
                optionalKeys = [
                    "lineHeight", "startInsetEm", "endInsetEm", "titleGapEm", "paddingBlockEm", "paddingInlineEm", "contentIndentEm", "quotationScale",
                    "attributionScale",
                ]
            } else if values["alignment"] != nil || values["weight"] != nil {
                optionalKeys = ["cjkStrongFontFamily", "cjkEmphasisFontFamily"]
            } else {
                optionalKeys = []
            }
            for key in optionalKeys where values[key] == nil { object.removeValue(forKey: key) }
            for (key, value) in values { object[key] = overlayConfiguration(object[key] ?? value, known: value) }
            return object
        }
        if let originals = original as? [Any], let values = known as? [Any] {
            var consumed: Set<Int> = []
            let overlaid = values.enumerated().map { index, value -> Any in
                let identity = (value as? [String: Any])?["role"] as? String
                let match =
                    identity.flatMap { role in originals.firstIndex { ($0 as? [String: Any])?["role"] as? String == role } }
                    ?? (identity == nil && originals.indices.contains(index) ? index : nil)
                guard let match else { return value }
                consumed.insert(match)
                return overlayConfiguration(originals[match], known: value)
            }
            return overlaid + originals.enumerated().filter { !consumed.contains($0.offset) }.map(\.element)
        }
        return known
    }

    public func restoreStyleSnippetDefaults() throws -> StyleSnapshot {
        ensureLoaded()
        try ensureDirectory()
        let current = fileManager.fileExists(atPath: manifestURL.path) ? try readRecoveryBytes(at: manifestURL) : nil
        // Retain every managed CSS file. Persist disabled registrations so the
        // next folder reconciliation cannot silently enable them again.
        let records = try discoveredSnippetURLs().map { url in
            CSSSnippetRecord(
                id: UUID(), name: url.deletingPathExtension().lastPathComponent,
                managedFileName: url.lastPathComponent, isEnabled: false)
        }
        let bytes = try JSONEncoder().encode(records)
        try coordinatedReplace(at: manifestURL, bytes: bytes, expected: current, preservingOriginal: true)
        loadedSnippetBytes = bytes
        snippets = records.map(normalizedSnippetRecord)
        manifestLoadFailure = nil
        rebuildCSS()
        storeError = nil
        return snapshot()
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

    private func recoverAppearance(_ bytes: Data) -> AppearanceManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            let objects = root["profiles"] as? [Any], objects.count <= 100
        else { return nil }
        var recovered: [DocumentAppearanceProfile] = []
        for rawObject in objects {
            guard let object = rawObject as? [String: Any], let rawID = object["id"] as? String, let id = UUID(uuidString: rawID),
                !recovered.contains(where: { $0.id == id })
            else { continue }
            let defaults = DocumentAppearanceProfile(name: "Custom")
            guard let baselineBytes = try? JSONEncoder().encode(defaults),
                let baseline = try? JSONSerialization.jsonObject(with: baselineBytes)
            else { continue }
            var candidate: Any = object
            for _ in 0..<100 {
                guard let data = try? JSONSerialization.data(withJSONObject: candidate) else { break }
                do {
                    let profile = try JSONDecoder().decode(DocumentAppearanceProfile.self, from: data)
                    recovered.append(normalized(profile))
                    break
                } catch let error as DecodingError {
                    let path: [String]
                    switch error {
                    case .keyNotFound(let key, let context): path = context.codingPath.map(\.stringValue) + [key.stringValue]
                    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                        path = context.codingPath.map(\.stringValue)
                    @unknown default: path = []
                    }
                    guard !path.isEmpty, path.first != "id",
                        let repaired = replacingConfigurationValue(at: path, in: candidate, with: configurationValue(at: path, in: baseline) ?? NSNull())
                    else { break }
                    candidate = repaired
                } catch { break }
            }
        }
        guard let first = recovered.first else { return nil }
        let requestedID = (root["selectedProfileID"] as? String).flatMap(UUID.init(uuidString:))
        return AppearanceManifest(selectedProfileID: recovered.first(where: { $0.id == requestedID })?.id ?? first.id, profiles: recovered)
    }

    private nonisolated func configurationValue(at path: [String], in value: Any) -> Any? {
        guard let key = path.first else { return value }
        if let object = value as? [String: Any], let next = object[key] {
            return configurationValue(at: Array(path.dropFirst()), in: next)
        }
        if let values = value as? [Any], let index = configurationIndex(key), values.indices.contains(index) {
            return configurationValue(at: Array(path.dropFirst()), in: values[index])
        }
        return nil
    }

    private nonisolated func replacingConfigurationValue(at path: [String], in value: Any, with replacement: Any) -> Any? {
        guard let key = path.first else { return replacement }
        let remaining = Array(path.dropFirst())
        if var object = value as? [String: Any] {
            guard let repaired = replacingConfigurationValue(at: remaining, in: object[key] ?? [:], with: replacement) else { return nil }
            object[key] = repaired
            return object
        }
        if var values = value as? [Any], let index = configurationIndex(key), values.indices.contains(index),
            let repaired = replacingConfigurationValue(at: remaining, in: values[index], with: replacement)
        {
            values[index] = repaired
            return values
        }
        return nil
    }

    private nonisolated func configurationIndex(_ key: String) -> Int? {
        Int(key) ?? Int(key.replacingOccurrences(of: "Index ", with: ""))
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
