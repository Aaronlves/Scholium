import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("External Markdown Import destination and exact source", .serialized)
struct ExternalMarkdownImportTests {
    @Test(
        "The external-window Import path normalizes supported names and preserves source and collisions",
        arguments: ["External 中文.markdown", "External 中文.MARKDOWN", "External 中文.md"])
    func supportedSourceImports(filename: String) async throws {
        try await withDestination { store, root, assignment, defaultID in
            let originalURL = root.appendingPathComponent(filename)
            let bytes = Data("\u{FEFF}---\r\nunknown: [unclosed # exact source\r\n---\r\n# 中文 😀\r\nTail without newline".utf8)
            try bytes.write(to: originalURL)
            let model = ExternalMarkdownWindowModel(url: originalURL)
            defer { model.close() }
            await model.open()
            #expect(model.title == filename)
            #expect(model.canImport)
            let captured = try await model.captureImport()
            #expect(captured == bytes)
            let destination = try #require(assignment.vault(for: .output))
            let folder = URL(fileURLWithPath: destination.canonicalPath)
            let existing = folder.appendingPathComponent("External 中文.md")
            let existingBytes = Data("# Existing destination must remain\r\n".utf8)
            try existingBytes.write(to: existing)

            let (first, firstOutcome) = try await store.importExternalMarkdown(
                captured, filename: model.title, assignment: assignment, slot: .output)
            let (second, _) = try await store.importExternalMarkdown(
                captured, filename: model.title, assignment: assignment, slot: .output)
            #expect(first.relativePath == "External 中文 2.md")
            #expect(second.relativePath == "External 中文 3.md")
            #expect(first.vaultID == destination.id && second.vaultID == destination.id)
            #expect(firstOutcome.committedValue.relativePath == first.relativePath)
            #expect(firstOutcome.identityRecoveryWarning == nil)
            #expect(try Data(contentsOf: folder.appendingPathComponent(first.relativePath)) == bytes)
            #expect(try Data(contentsOf: folder.appendingPathComponent(second.relativePath)) == bytes)
            #expect(try Data(contentsOf: existing) == existingBytes)
            #expect(try Data(contentsOf: originalURL) == bytes)
            #expect(Data(try #require(model.snapshot).source.utf8) == bytes && !model.isDirty)
            #expect(try await store.defaultTriptych().id == defaultID)
            #expect(assignment.id != defaultID)
            let handle = try await store.applicationRuntime.openWorkspace(id: assignment.id)
            let snapshot = try await handle.snapshot()
            #expect(
                snapshot.document(id: .init(vaultID: destination.id, relativePath: first.relativePath))?.fingerprint == firstOutcome.committedValue.fingerprint)
            for slot in [WorkspaceVaultSlot.paperAnalysis, .topicKnowledge] {
                let vault = try #require(assignment.vault(for: slot))
                #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: vault.canonicalPath).appendingPathComponent(first.relativePath).path))
            }
            let defaults = try #require(try await store.registeredTriptychs().first { $0.id == defaultID })
            for vault in defaults.vaults.values {
                #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: vault.canonicalPath).appendingPathComponent(first.relativePath).path))
            }
        }
    }

    @Test(
        "External Import rejects invalid names and encoding before creating source",
        arguments: ["../Escape.markdown", "Unsupported.txt", "Invalid UTF8.markdown"])
    func invalidImportCreatesNoSource(filename: String) async throws {
        try await withDestination { store, root, assignment, defaultID in
            let data = filename.hasPrefix("Invalid") ? Data([0xFF, 0xFE, 0x00]) : Data("# Synthetic\r\n".utf8)
            await #expect(throws: DocumentImportError.self) {
                _ = try await store.importExternalMarkdown(data, filename: filename, assignment: assignment, slot: .output)
            }
            for vault in assignment.vaults.values {
                let children = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: vault.canonicalPath), includingPropertiesForKeys: nil)
                #expect(!children.contains { ["md", "markdown"].contains($0.pathExtension.lowercased()) })
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Escape.md").path))
            #expect(try await store.defaultTriptych().id == defaultID)
        }
    }

    private func withDestination(_ body: (WorkspaceStore, URL, TriptychAssignment, UUID) async throws -> Void) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/ExternalMarkdownImportTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var createdStore: WorkspaceStore?
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
            createdStore = store
            var ids: [UUID] = []
            for name in ["Default", "Selected"] {
                let triptych = root.appendingPathComponent(name)
                let folders = ["Analyses", "Topics", "Works"].map { triptych.appendingPathComponent($0) }
                for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
                let capabilities = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: folders[0], topicKnowledgeURL: folders[1], outputURL: folders[2],
                    portableContainerURL: triptych, triptychName: name)
                ids.append(capabilities.id)
            }
            let destination = try #require(try await store.registeredTriptychs().first { $0.id == ids[1] })
            try await body(store, root, destination, ids[0])
            await store.shutdownApplicationRuntime()
        } catch {
            await createdStore?.shutdownApplicationRuntime()
            throw error
        }
    }
}
