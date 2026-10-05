import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Library mutation behavior")
@MainActor
struct WindowLibraryMutationBehaviorTests {
    @Test("Trash preview includes the draft saved by its editor flush callback", arguments: [false, true])
    func previewSavesEditor(folder: Bool) async throws {
        try await withFixture { fixture in
            let draft = fixture.original + "Researcher's unsaved café\r\n"
            fixture.draft = draft
            try await fixture.prepareTrash(folder: folder)

            let preview = try #require(fixture.preview)
            let source = try #require(preview.sources.first)
            #expect(source.kind == (folder ? .folder : .note))
            #expect(source.relativePath == (folder ? "Drafts" : "Drafts/Note.md"))
            #expect(source.notes.map(\.noteID) == [fixture.target.stableNoteID])
            #expect(source.notes.map(\.expectedRevision) == [DocumentFingerprint(content: draft)])
            #expect(try Data(contentsOf: fixture.file) == Data(draft.utf8))
            #expect(!fixture.hasUnsavedChanges)
            #expect(!fixture.controller.hasActiveLibraryMutation)
        }
    }

    @Test("A save conflict prevents Note and Folder Trash previews and preserves both sources", arguments: [false, true])
    func conflictStopsPreview(folder: Bool) async throws {
        try await withFixture { fixture in
            let draft = fixture.original + "Unsaved researcher input\n"
            let external = fixture.original + "Concurrent external input\n"
            fixture.draft = draft
            try Data(external.utf8).write(to: fixture.file)

            await #expect(throws: VaultRepositoryError.self) {
                try await fixture.prepareTrash(folder: folder)
            }
            #expect(fixture.preview == nil)
            #expect(fixture.draft == draft)
            #expect(fixture.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.file) == Data(external.utf8))
            #expect(!fixture.controller.isMutatingFolder)
            #expect(!fixture.controller.hasActiveLibraryMutation)
        }
    }

    @Test("A confirmed Trash preview cannot delete content saved after that preview")
    func staleTrashPreservesNewRevision() async throws {
        try await withFixture { fixture in
            try await fixture.prepareTrash(folder: false)
            let preview = try #require(fixture.preview)
            let draft = fixture.original + "Written after confirmation\n"
            fixture.draft = draft

            await #expect(throws: VaultRepositoryError.self) {
                try await fixture.controller.executeSystemTrash(preview)
            }
            #expect(try Data(contentsOf: fixture.file) == Data(draft.utf8))
            #expect(!fixture.hasUnsavedChanges)
            #expect(fixture.trashResultWasRejected)
            #expect(!fixture.controller.hasActiveLibraryMutation)
        }
    }

    @Test("A pending folder move rejects another move and Trash preview, then permits retry")
    func busyFolderRejectsConcurrentCommands() async throws {
        try await withFixture { fixture in
            let entered = AsyncStream<Void>.makeStream()
            let release = AsyncStream<Void>.makeStream()
            defer {
                entered.continuation.finish()
                release.continuation.finish()
            }
            var didSuspendFirstFlush = false
            fixture.beforeFlush = {
                guard !didSuspendFirstFlush else { return }
                didSuspendFirstFlush = true
                entered.continuation.yield(())
                for await _ in release.stream { break }
            }
            let first = Task { @MainActor in
                defer { entered.continuation.finish() }
                try await fixture.controller.moveFolder(fixture.folder, to: "Filed")
            }
            for await _ in entered.stream { break }
            #expect(fixture.controller.isMutatingFolder)

            let busyMessage = String(
                localized: "Another folder operation is already in progress.", table: "Localizable", bundle: .module)
            await #expect {
                try await fixture.controller.moveFolder(fixture.folder, to: "Other")
            } throws: { error in
                error.localizedDescription == busyMessage
            }
            await #expect {
                try await fixture.controller.prepareFolderSystemTrash(fixture.folder)
            } throws: { error in
                error.localizedDescription == busyMessage
            }
            #expect(fixture.preview == nil)
            #expect(FileManager.default.fileExists(atPath: fixture.file.path))
            #expect(!FileManager.default.fileExists(atPath: fixture.vaultURL.appendingPathComponent("Other").path))

            fixture.beforeFlush = {}
            release.continuation.yield(())
            try await first.value
            #expect(!fixture.controller.isMutatingFolder)
            #expect(!fixture.controller.hasActiveLibraryMutation)
            let moved = fixture.vaultURL.appendingPathComponent("Filed/Note.md")
            #expect(try Data(contentsOf: moved) == Data(fixture.original.utf8))
            #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
            try await fixture.controller.prepareFolderSystemTrash(.init(vaultID: fixture.vault.id, relativePath: "Filed"))
            #expect(fixture.preview?.sources.first?.relativePath == "Filed")
        }
    }

    private func withFixture(_ body: @MainActor (LibraryMutationFixture) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/library-mutation-behavior-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let fixture = try await LibraryMutationFixture.make(root: root, store: store)
            defer {
                fixture.controller.unbind()
                // A regression could unexpectedly trash this disposable Note.
                // Clean only the system receipt paths for this fixture's identity.
                for path in fixture.trashedFixturePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            try await body(fixture)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}

@MainActor
private final class LibraryMutationFixture {
    // Substitute only the editor's flush boundary; persistence, conflict checks,
    // and deletion previews use the real workspace on disposable files.
    let capabilities: WindowWorkspaceCapabilities
    let vault: RegisteredVault
    let file: URL
    let original: String
    var draft: String
    var revision: DocumentFingerprint
    var hasUnsavedChanges: Bool { DocumentFingerprint(content: draft) != revision }
    let target: NoteMutationTarget
    var preview: SystemTrashDeletionPreview?
    var trashResultWasRejected = false
    var trashedFixturePaths: [String] = []
    var beforeFlush: @MainActor () async -> Void = {}
    var vaultURL: URL { URL(fileURLWithPath: vault.canonicalPath) }
    var folder: FolderMutationTarget { .init(vaultID: vault.id, relativePath: "Drafts") }

    lazy var controller: WindowLibraryMutationController = {
        let controller = WindowLibraryMutationController(
            dependencies: .init(
                context: { [unowned self] in .init(assignmentID: capabilities.assignment.id, vault: vault, sourceScope: .library) },
                enqueueDocumentTransition: { _, _, _ in Issue.record("Unexpected Note creation") },
                flushEditors: { [unowned self] _ in try await flushDraft() },
                flushActiveTarget: { _ in Issue.record("Unexpected active-target flush") },
                expectedRevision: { [unowned self] _ in revision },
                captureBatchTargets: { $0 },
                committedNoteCreated: { _, _ in }, committedFolderCreated: { _ in },
                committedFolderMoved: { _ in }, committedNoteDuplicated: { _, _, _ in }, committedNoteMoved: { _, _ in },
                committedSystemTrash: { [unowned self] _, outcome in
                    trashResultWasRejected = outcome == nil
                    if let commit = outcome?.committedValue, commit.noteIDs == [target.stableNoteID] {
                        trashedFixturePaths = commit.resultingTrashPaths
                    }
                },
                importedDocumentsCommitted: { _ in }, presentImportOutcome: { _ in },
                presentSystemTrash: { [unowned self] in preview = $0 }, clearPresentedAlert: {},
                reportError: { Issue.record(Comment(rawValue: $0)) }, reportInformation: { _ in }, refreshTransactionRecovery: {}))
        controller.bind(to: capabilities.libraryMutations)
        return controller
    }()

    private func flushDraft() async throws {
        await beforeFlush()
        guard hasUnsavedChanges else { return }
        let result = try await capabilities.documents.save(
            NoteMutationTarget(documentID: target.documentID, stableNoteID: target.stableNoteID, revision: revision),
            changeSet: .source(draft))
        revision = result.committedValue.document.fingerprint
    }

    private init(capabilities: WindowWorkspaceCapabilities, vault: RegisteredVault, file: URL, snapshot: WorkspaceNoteSnapshot) throws {
        self.capabilities = capabilities
        self.vault = vault
        self.file = file
        original = snapshot.document.rawContent
        draft = original
        revision = snapshot.fingerprint
        target = .init(documentID: snapshot.id, stableNoteID: try #require(snapshot.stableIdentity.resolvedID), revision: snapshot.fingerprint)
    }

    static func make(root: URL, store: WorkspaceStore) async throws -> LibraryMutationFixture {
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let folder = vaults[1].appendingPathComponent("Drafts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Note.md")
        let source = "\u{feff}---\r\nid: \(UUID().uuidString.lowercased())\r\ncustom: 'keep' # exact\r\n---\r\nOriginal\r\n"
        try Data(source.utf8).write(to: file)
        let capabilities = try await store.configureTriptychCapabilities(
            paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
            portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Library mutation fixture")
        let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
        let snapshot = try #require(vault.documents.first { $0.id.relativePath == "Drafts/Note.md" })
        let hydrated = try await capabilities.documents.hydrate(snapshot)
        return try .init(capabilities: capabilities, vault: vault.vault, file: file, snapshot: hydrated)
    }

    func prepareTrash(folder: Bool) async throws {
        if folder {
            try await controller.prepareFolderSystemTrash(self.folder)
        } else {
            try await controller.prepareNoteSystemTrash(target)
        }
    }
}
