import AppKit
import Combine
import Foundation
import ScholiumCore

struct CSSSnippetRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let managedFileName: String
    var isEnabled: Bool
    var sourceFingerprint: String?
    var lastFailure: String?

    init(
        id: UUID,
        name: String,
        managedFileName: String,
        isEnabled: Bool,
        sourceFingerprint: String? = nil,
        lastFailure: String? = nil
    ) {
        self.id = id
        self.name = name
        self.managedFileName = managedFileName
        self.isEnabled = isEnabled
        self.sourceFingerprint = sourceFingerprint
        self.lastFailure = lastFailure
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, managedFileName, isEnabled, sourceFingerprint, lastFailure
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        managedFileName = try values.decode(String.self, forKey: .managedFileName)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        sourceFingerprint = try values.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        lastFailure = try values.decodeIfPresent(String.self, forKey: .lastFailure)
    }
}

private enum CSSSnippetStoreError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "CSS snippet settings are unavailable: \(reason) Reveal the managed folder in Finder and repair or remove snippets.json before making changes."
        }
    }
}

@MainActor
final class CSSSnippetStore: ObservableObject {
    @Published private(set) var snippets: [CSSSnippetRecord] = []
    @Published private(set) var validationErrors: [UUID: String] = [:]
    @Published private(set) var readCSS = ""
    @Published private(set) var livePreviewCSS = ""
    @Published private(set) var safeModeReason: String?
    @Published private(set) var storeError: String?

    private let fileManager: FileManager
    private let directoryURL: URL
    private let manifestURL: URL
    private let safeModeURL: URL
    private var manifestLoadFailure: Error?

    init(applicationSupportURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = applicationSupportURL
            .appendingPathComponent("Workspace", isDirectory: true)
            .appendingPathComponent("Styles", isDirectory: true)
            .appendingPathComponent("Snippets", isDirectory: true)
        manifestURL = directoryURL.deletingLastPathComponent().appendingPathComponent("snippets.json")
        safeModeURL = directoryURL.deletingLastPathComponent().appendingPathComponent("css-safe-mode.txt")
        load()
    }

    var enabledCount: Int { snippets.lazy.filter(\.isEnabled).count }
    var canModify: Bool { manifestLoadFailure == nil }

    func importSnippet(from sourceURL: URL) throws {
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
        let destination = directoryURL.appendingPathComponent(managedFileName, isDirectory: false)
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
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        mutate { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == id }) else { return false }
            candidate[index].isEnabled = enabled
            return true
        }
    }

    func move(_ id: UUID, by offset: Int) {
        mutate { candidate in
            guard let source = candidate.firstIndex(where: { $0.id == id }) else { return false }
            let destination = source + offset
            guard candidate.indices.contains(destination) else { return false }
            let record = candidate.remove(at: source)
            candidate.insert(record, at: destination)
            return true
        }
    }

    func rename(_ id: UUID, to requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutate { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == id }) else { return false }
            candidate[index].name = name
            return true
        }
    }

    func duplicate(_ id: UUID) {
        guard let source = snippets.first(where: { $0.id == id }) else { return }
        let sourceURL = directoryURL.appendingPathComponent(source.managedFileName)
        guard let data = try? Data(contentsOf: sourceURL) else { return }
        let copyID = UUID()
        let fileName = copyID.uuidString.lowercased() + ".css"
        let target = directoryURL.appendingPathComponent(fileName)
        do {
            try data.write(to: target, options: .atomic)
            let copy = CSSSnippetRecord(
                id: copyID,
                name: source.name + " Copy",
                managedFileName: fileName,
                isEnabled: source.isEnabled,
                sourceFingerprint: source.sourceFingerprint
            )
            do {
                try requireWritableManifest()
                try commit(snippets + [copy], clearingSafeMode: true)
            } catch {
                try? fileManager.removeItem(at: target)
                throw error
            }
        } catch {
            storeError = "Scholium could not duplicate the CSS snippet: \(error.localizedDescription)"
        }
    }

    func reload(_ id: UUID) {
        guard snippets.contains(where: { $0.id == id }) else { return }
        do {
            try requireWritableManifest()
            try commit(snippets, clearingSafeMode: false)
        } catch {
            storeError = error.localizedDescription
        }
    }

    func editManagedCopy(_ id: UUID) {
        guard let record = snippets.first(where: { $0.id == id }) else { return }
        let url = directoryURL.appendingPathComponent(record.managedFileName)
        guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL else { return }
        NSWorkspace.shared.open(url)
    }

    func remove(_ id: UUID) {
        guard let record = snippets.first(where: { $0.id == id }) else { return }
        do {
            try requireWritableManifest()
            try commit(snippets.filter { $0.id != id }, clearingSafeMode: true)
            let candidate = directoryURL.appendingPathComponent(record.managedFileName, isDirectory: false)
            if candidate.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL {
                try? fileManager.removeItem(at: candidate)
            }
        } catch {
            storeError = error.localizedDescription
        }
    }

    func disableAll() {
        mutate { candidate in
            for index in candidate.indices { candidate[index].isEnabled = false }
            return true
        }
    }

    func enterSafeMode(after reason: String) {
        guard enabledCount > 0, manifestLoadFailure == nil else { return }
        var candidate = snippets
        for index in candidate.indices { candidate[index].isEnabled = false }
        do {
            try commit(candidate, clearingSafeMode: false)
            try Data(reason.utf8).write(to: safeModeURL, options: .atomic)
            safeModeReason = reason
        } catch {
            storeError = "Scholium could not enter CSS Safe Mode: \(error.localizedDescription)"
            // Rendering remains protected even when persistence failed.
            readCSS = ""
            livePreviewCSS = ""
            safeModeReason = reason
        }
    }

    func revealManagedFolder() {
        do {
            try ensureDirectory()
            let selection = fileManager.fileExists(atPath: manifestURL.path) ? manifestURL : directoryURL
            NSWorkspace.shared.activateFileViewerSelecting([selection])
        } catch {
            storeError = error.localizedDescription
        }
    }

    private func load() {
        do {
            try ensureDirectory()
            if fileManager.fileExists(atPath: manifestURL.path) {
                let data = try Data(contentsOf: manifestURL)
                snippets = try JSONDecoder().decode([CSSSnippetRecord].self, from: data)
            }
            if fileManager.fileExists(atPath: safeModeURL.path),
               let persisted = String(data: try Data(contentsOf: safeModeURL), encoding: .utf8),
               !persisted.isEmpty {
                safeModeReason = persisted
                for index in snippets.indices { snippets[index].isEnabled = false }
            }
            try rebuildCSS()
        } catch {
            manifestLoadFailure = error
            snippets = []
            validationErrors = [:]
            readCSS = ""
            livePreviewCSS = ""
            storeError = CSSSnippetStoreError.unavailable(error.localizedDescription).localizedDescription
            safeModeReason = "Scholium disabled document CSS because its snippet settings could not be read."
        }
    }

    private func requireWritableManifest() throws {
        if let manifestLoadFailure {
            throw CSSSnippetStoreError.unavailable(manifestLoadFailure.localizedDescription)
        }
    }

    private func mutate(_ change: (inout [CSSSnippetRecord]) -> Bool) {
        do {
            try requireWritableManifest()
            var candidate = snippets
            guard change(&candidate) else { return }
            try commit(candidate, clearingSafeMode: true)
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// Publishes UI state only after the candidate manifest is durably written.
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

    private func rebuildCSS() throws {
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
                let url = directoryURL.appendingPathComponent(snippet.managedFileName, isDirectory: false)
                guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL else {
                    throw CSSSnippetSanitizationError.forbiddenConstruct("managed path escape")
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
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

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
