import Foundation
import ScholiumContracts

/// Owns every persisted CSS-snippet byte under Application Support. The
/// frontend receives immutable snapshots and may only present returned URLs.
public actor StyleOperations: StyleUseCases {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let manifestURL: URL
    private let safeModeURL: URL

    private var snippets: [CSSSnippetRecord] = []
    private var validationErrors: [UUID: String] = [:]
    private var readCSS = ""
    private var livePreviewCSS = ""
    private var safeModeReason: String?
    private var storeError: String?
    private var manifestLoadFailure: Error?
    private var didLoad = false

    public init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = applicationSupportURL
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
            .appendingPathComponent("Snippets", isDirectory: true)
        manifestURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("snippets.json")
        safeModeURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent("css-safe-mode.txt")
    }

    public func styleSnapshot() throws -> StyleSnapshot {
        ensureLoaded()
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
            name: displayName.isEmpty ? "CSS Snippet" : displayName,
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
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            name: source.name + " Copy",
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
        return fileManager.fileExists(atPath: manifestURL.path) ? manifestURL : directoryURL
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
           let object = jsonObject(at: obsidianURL.appendingPathComponent("appearance.json")) {
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
                snippets = try JSONDecoder().decode(
                    [CSSSnippetRecord].self,
                    from: Data(contentsOf: manifestURL)
                )
            }
            if fileManager.fileExists(atPath: safeModeURL.path),
               let persisted = String(data: try Data(contentsOf: safeModeURL), encoding: .utf8),
               !persisted.isEmpty {
                safeModeReason = persisted
                for index in snippets.indices { snippets[index].isEnabled = false }
            }
            rebuildCSS()
        } catch {
            manifestLoadFailure = error
            snippets = []
            validationErrors = [:]
            readCSS = ""
            livePreviewCSS = ""
            storeError = StyleUseCaseError.unavailable(error.localizedDescription).localizedDescription
            safeModeReason = "Scholium disabled document CSS because its snippet settings could not be read."
        }
    }

    private func snapshot() -> StyleSnapshot {
        StyleSnapshot(
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

    private func rebuildCSS() {
        let build = buildCSS(from: snippets)
        snippets = build.snippets
        validationErrors = build.errors
        readCSS = build.readCSS
        livePreviewCSS = build.livePreviewCSS
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
        for index in records.indices where records[index].isEnabled {
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
                read.append("/* \(snippet.name) */\n\(projection.readCSS)")
                live.append("/* \(snippet.name) */\n\(projection.livePreviewCSS)")
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

    private func managedURL(for record: CSSSnippetRecord) throws -> URL {
        let url = directoryURL.appendingPathComponent(record.managedFileName).standardizedFileURL
        guard url.deletingLastPathComponent() == directoryURL.standardizedFileURL else {
            throw CSSSnippetSanitizationError.forbiddenConstruct("managed path escape")
        }
        return url
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
