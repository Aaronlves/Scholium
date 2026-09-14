import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window merge property decisions", .serialized)
@MainActor
struct NoteRestructureWindowTests {
    @Test("Preview preserves property choices and refuses rebasing them onto a changed destination")
    func exactPropertyChoice() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/merge-window-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let source = "---\nstatus: 'draft' # source\n---\nSource argument.\n"
        let target = "---\nstatus: 'final' # destination\n---\nTarget argument.\n"
        let sourceURL = vaults[1].appendingPathComponent("Source.md")
        let targetURL = vaults[1].appendingPathComponent("Target.md")
        try Data(source.utf8).write(to: sourceURL)
        try Data(target.utf8).write(to: targetURL)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Merge fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.topicKnowledge)
            let catalog = try #require(window.workspaceCatalog)
            func mutation(_ name: String) throws -> NoteMutationTarget {
                let note = try #require(catalog.notes.first { $0.reference.relativePath == name })
                return .init(
                    documentID: .init(vaultID: note.reference.vaultID, relativePath: name),
                    stableNoteID: try #require(note.reference.stableNoteID.flatMap(UUID.init(uuidString:))), revision: note.fingerprint)
            }
            let request = NoteRestructureRequest(
                source: try mutation("Source.md"), selectionUTF8: nil,
                destination: .existing(try mutation("Target.md")), operation: .merge, propertyResolutions: ["status": .useSource])
            let preview = try await window.prepareNoteRestructure(request)
            #expect(preview.request == request)
            #expect(
                preview.edits.first(where: { $0.note.relativePath == "Target.md" })?.after
                    == "---\nstatus: 'draft' # source\n---\nTarget argument.\n\nSource argument.\n")
            #expect(try Data(contentsOf: sourceURL) == Data(source.utf8))
            #expect(try Data(contentsOf: targetURL) == Data(target.utf8))
            let external = target.replacingOccurrences(of: "'final'", with: "'externally changed'")
            try Data(external.utf8).write(to: targetURL)
            await #expect(throws: (any Error).self) { try await window.prepareNoteRestructure(request) }
            #expect(try Data(contentsOf: targetURL) == Data(external.utf8))
            await window.chatController?.disconnect()
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
