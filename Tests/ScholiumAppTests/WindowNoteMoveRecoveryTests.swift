import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window Note move recovery", .serialized)
@MainActor
struct WindowNoteMoveRecoveryTests {
    @Test("Note moves preserve the open session and retarget every history visit through nested and root locations")
    func moveRetainsDocumentAndHistory() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        do {
            let window = fixture.window
            let original = try #require(window.currentDocumentDescriptor)
            try await window.openNote("Other.md")
            try await window.openNote("Nested/Note.md")
            let session = window.documentController.session(for: original.sessionKey)
            let count = window.documentNavigationHistoryController.count
            for destination in ["Sibling/Note.md", "Note.md", "Nested/Note.md"] {
                let current = try #require(window.currentNote)
                let target = try #require(NoteMutationTarget(current))
                try await window.libraryMutationController.moveNote(target, to: destination)
                await window.retryDerivedRefresh()
                #expect(window.currentDocumentDescriptor?.sessionKey == original.sessionKey)
                #expect(window.currentDocumentDescriptor?.reference.relativePath == destination)
                #expect(window.documentController.session(for: original.sessionKey) === session)
                #expect(window.documentNavigationHistoryController.count == count)
                #expect(window.shellState.operationIssues.isEmpty)
                #expect(try Data(contentsOf: fixture.topics.appendingPathComponent(destination)) == Fixture.source)
                let history = window.documentNavigationHistoryController
                let other = try #require(history.target(for: .back))
                #expect(other.relativePath == "Other.md")
                #expect(history.commit(.back, to: other))
                #expect(history.target(for: .back)?.relativePath == destination)
                let forward = try #require(history.target(for: .forward))
                #expect(history.commit(.forward, to: forward))
            }
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @Test("A peer refresh retains a pending moved identity, rejects former-path reuse and repairs without moving again")
    func retryRepairsCommittedMove() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        do {
            let window = fixture.window
            let original = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: original.sessionKey)
            let current = try #require(window.currentNote)
            let target = try #require(NoteMutationTarget(current))
            let sessions = fixture.support.appendingPathComponent("Window Sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let blocked = sessions.appendingPathComponent(UUID().uuidString + ".json")
            let corruptBytes = Data("{ synthetic corrupt session".utf8)
            try corruptBytes.write(to: blocked)

            // Move through the shared Application owner, without the initiating
            // window's local path projection. This window is a publication peer.
            let outcome = try await fixture.capabilities.libraryMutations.move(target, to: "Note.md")
            #expect(outcome.identityRecoveryWarning != nil)
            window.reportCommittedMutationWarnings(outcome)
            #expect(!FileManager.default.fileExists(atPath: fixture.topics.appendingPathComponent("Nested/Note.md").path))
            #expect(try Data(contentsOf: fixture.topics.appendingPathComponent("Note.md")) == Fixture.source)
            #expect(window.shellState.operationIssues.contains { $0.kind == .warning && $0.offersRefresh })
            await window.retryDerivedRefresh()
            #expect(window.currentDocumentDescriptor?.sessionKey == original.sessionKey)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == "Note.md")
            #expect(window.documentController.session(for: original.sessionKey) === session)
            #expect(!window.identityMigrationFailures.isEmpty)
            #expect(window.currentNote?.workspaceSnapshot?.stableIdentity == .pending(original.sessionKey.noteID))
            #expect(!window.currentDocumentCapabilities.canEditSource)
            #expect(try Data(contentsOf: blocked) == corruptBytes)

            let replacement = Data("Unrelated replacement at the former path.\n".utf8)
            try FileManager.default.createDirectory(at: fixture.topics.appendingPathComponent("Nested"), withIntermediateDirectories: true)
            try replacement.write(to: fixture.topics.appendingPathComponent("Nested/Note.md"))
            await window.retryDerivedRefresh()
            #expect(window.currentDocumentDescriptor?.sessionKey == original.sessionKey)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == "Note.md")
            #expect(window.documentController.session(for: original.sessionKey) === session)

            // Synthetic record repair is test-owned; the product retry only
            // replays retained app-owned migration and reads current source.
            try FileManager.default.removeItem(at: blocked)
            await window.retryIdentityRecovery()
            await window.retryDerivedRefresh()
            #expect(window.identityMigrationFailures.isEmpty)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == "Note.md")
            #expect(window.currentDocumentDescriptor?.sessionKey == original.sessionKey)
            #expect(window.documentController.session(for: original.sessionKey) === session)
            #expect(window.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID == original.sessionKey.noteID)
            #expect(window.documentNavigationHistoryController.currentDocument?.relativePath == "Note.md")
            #expect(try Data(contentsOf: fixture.topics.appendingPathComponent("Note.md")) == Fixture.source)
            #expect(try Data(contentsOf: fixture.topics.appendingPathComponent("Nested/Note.md")) == replacement)
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @MainActor
    private struct Fixture {
        static let source = Data("\u{FEFF}---\r\ncustom: 'keep' # exact\r\n---\r\n\r\nSynthetic note without a final newline.".utf8)
        let root: URL
        let topics: URL
        let support: URL
        let store: WorkspaceStore
        let capabilities: WindowWorkspaceCapabilities
        let window: WindowModel

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/window-note-move-tests/\(UUID())")
            let triptych = root.appendingPathComponent("Triptych")
            let roots = ["Analyses", "Topics", "Works"].map { triptych.appendingPathComponent($0) }
            let support = root.appendingPathComponent("Support")
            var store: WorkspaceStore?
            do {
                for directory in roots { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                for folder in ["Nested", "Sibling"] {
                    try FileManager.default.createDirectory(at: roots[1].appendingPathComponent(folder), withIntermediateDirectories: true)
                }
                try source.write(to: roots[1].appendingPathComponent("Nested/Note.md"))
                try Data("Independent note.\n".utf8).write(to: roots[1].appendingPathComponent("Other.md"))
                let created = try WorkspaceStore(applicationSupportURL: support)
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: roots[0], topicKnowledgeURL: roots[1], outputURL: roots[2],
                    portableContainerURL: triptych, triptychName: "Note move fixture")
                let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
                try await window.openWorkspaceVault(.topicKnowledge)
                window.documentController.rememberPresentationMode(.read)
                try await window.openNote("Nested/Note.md")
                return Fixture(root: root, topics: roots[1], support: support, store: created, capabilities: capabilities, window: window)
            } catch {
                await store?.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func shutdown() async {
            window.windowCloseCoordinator.finalize()
            await store.shutdownApplicationRuntime()
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
