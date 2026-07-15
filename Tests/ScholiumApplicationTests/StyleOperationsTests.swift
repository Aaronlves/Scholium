import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Application-owned style I/O")
struct StyleOperationsTests {
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
