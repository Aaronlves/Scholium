import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Authored document attachment opening", .serialized)
@MainActor
struct AuthoredDocumentAttachmentPreviewTests {
    @Test("An absolute link asks once for its exact original and preserves source")
    func exactOriginalOpensWithoutInsertion() async throws {
        try await withFixture { fixture async throws in
            let controller = DocumentController()
            controller.bind(to: fixture.documents)
            defer { controller.unbind() }
            var selections = 0
            let access = try await controller.prepareAuthoredDocumentAttachmentPreview(
                destination: fixture.original.path, for: fixture.target, isCurrent: { true }
            ) { request in
                selections += 1
                #expect(request.initialDirectoryURL == fixture.original.deletingLastPathComponent())
                #expect(!request.makePanel().resolvesAliases)
                return try request.validatedURLs([fixture.original]).first
            }
            #expect(access.lease.fileURL.path == fixture.original.path)
            await access.release()
            let second = try await controller.prepareAuthoredDocumentAttachmentPreview(
                destination: fixture.original.path, for: fixture.target, isCurrent: { true }
            ) { _ in
                Issue.record("An available exact-file grant must not reopen the chooser.")
                return nil
            }
            await second.release()
            #expect(selections == 1)
            #expect(try await fixture.documents.load(fixture.id).sourceBytes == Data(fixture.source.utf8))
            #expect(try await fixture.documents.documentAttachments(for: fixture.target).count == 1)
        }
    }

    @Test("Chooser cancellation, same-name substitution and a stale context create no grant")
    func rejectedSelectionPreservesState() async throws {
        try await withFixture { fixture async throws in
            let controller = DocumentController()
            controller.bind(to: fixture.documents)
            defer { controller.unbind() }
            await #expect(throws: CancellationError.self) {
                _ = try await controller.prepareAuthoredDocumentAttachmentPreview(
                    destination: fixture.original.path, for: fixture.target, isCurrent: { true },
                    selectFile: { _ in nil })
            }
            let otherDirectory = fixture.root.appendingPathComponent("Other")
            try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: false)
            let substituted = otherDirectory.appendingPathComponent(fixture.original.lastPathComponent)
            try Data("different synthetic file".utf8).write(to: substituted)
            await #expect(throws: DocumentAttachmentError.self) {
                _ = try await controller.prepareAuthoredDocumentAttachmentPreview(
                    destination: fixture.original.path, for: fixture.target, isCurrent: { true },
                    selectFile: { _ in substituted })
            }
            var isCurrent = true
            await #expect(throws: CancellationError.self) {
                _ = try await controller.prepareAuthoredDocumentAttachmentPreview(
                    destination: fixture.original.path, for: fixture.target, isCurrent: { isCurrent }
                ) { _ in
                    isCurrent = false
                    return fixture.original
                }
            }
            #expect(try await fixture.documents.sourceAttachment(for: fixture.original.path, target: fixture.target) == nil)
            #expect(try await fixture.documents.load(fixture.id).sourceBytes == Data(fixture.source.utf8))
        }
    }

    @Test("Source drift during the chooser is rejected before registering read access")
    func changedSourceCannotGrantAccess() async throws {
        try await withFixture { fixture async throws in
            let controller = DocumentController()
            controller.bind(to: fixture.documents)
            defer { controller.unbind() }
            let changedSource = "The researcher removed the link.\n"
            await #expect(throws: DocumentAttachmentError.self) {
                _ = try await controller.prepareAuthoredDocumentAttachmentPreview(
                    destination: fixture.original.path, for: fixture.target, isCurrent: { true }
                ) { _ in
                    _ = try await fixture.documents.commit(
                        NoteMutationTarget(
                            documentID: fixture.id, stableNoteID: fixture.target.noteID,
                            revision: DocumentFingerprint(data: Data(fixture.source.utf8))),
                        changeSet: .source(changedSource))
                    return fixture.original
                }
            }
            #expect(try await fixture.documents.sourceAttachment(for: fixture.original.path, target: fixture.target) == nil)
            #expect(try await fixture.documents.load(fixture.id).rawContent == changedSource)
        }
    }

    @Test("A context superseded after authorization rolls back only its new grant")
    func lateContextChangeCleansNewPreparation() async throws {
        try await withFixture { fixture async throws in
            let controller = DocumentController()
            controller.bind(to: fixture.documents)
            defer { controller.unbind() }
            #expect(!FileManager.default.fileExists(atPath: fixture.localAccessRecord.path))
            await #expect(throws: CancellationError.self) {
                _ = try await controller.prepareAuthoredDocumentAttachmentPreview(
                    destination: fixture.original.path, for: fixture.target,
                    isCurrent: {
                        // Simulate navigation as soon as the new local grant
                        // exists, independently of the controller's check count.
                        !FileManager.default.fileExists(atPath: fixture.localAccessRecord.path)
                    }, selectFile: { _ in fixture.original })
            }
            #expect(FileManager.default.fileExists(atPath: fixture.localAccessRecord.path))
            #expect(try await fixture.documents.sourceAttachment(for: fixture.original.path, target: fixture.target) == nil)
            #expect(try await fixture.documents.load(fixture.id).sourceBytes == Data(fixture.source.utf8))
            #expect(FileManager.default.fileExists(atPath: fixture.original.path))
        }
    }

    @Test("A contained relative PDF opens without an external-file chooser")
    func relativeDocumentKeepsExistingRoute() async throws {
        try await withFixture(relative: true) { fixture async throws in
            let controller = DocumentController()
            controller.bind(to: fixture.documents)
            defer { controller.unbind() }
            let access = try await controller.prepareAuthoredDocumentAttachmentPreview(
                destination: "Original.pdf", for: fixture.target, isCurrent: { true }
            ) { _ in
                Issue.record("A contained file must use the registered vault's existing authority.")
                return nil
            }
            #expect(access.lease.fileURL.path == fixture.original.path)
            await access.release()
        }
    }

    private func withFixture(
        relative: Bool = false,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let fixture = try await Fixture.make(relative: relative)
        do {
            try await body(fixture)
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            try? FileManager.default.removeItem(at: fixture.root)
            throw error
        }
        await fixture.store.shutdownApplicationRuntime()
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private struct Fixture {
        let root: URL
        let original: URL
        let source: String
        let localAccessRecord: URL
        let store: WorkspaceStore
        let documents: any DocumentUseCases
        let id: VaultQualifiedNoteID
        let target: SourceAttachmentTarget

        @MainActor
        static func make(relative: Bool) async throws -> Self {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/authored-document-preview-tests/\(UUID())")
                .resolvingSymlinksInPath().standardizedFileURL
            let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
            for vault in vaults {
                try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            }
            let original =
                relative
                ? vaults[0].appendingPathComponent("Original.pdf")
                : root.appendingPathComponent("原文 e\u{301} (2).pdf")
            try Data("Disposable attachment fixture, with no real PDF content.".utf8).write(to: original)
            let destination = relative ? "Original.pdf" : original.path
            let source = "\u{FEFF}---\r\ncustom: 'retained'\r\n---\r\n> [!info] 来源\r\n> [PDF](<\(destination)>)\r\n"
            try Data(source.utf8).write(to: vaults[0].appendingPathComponent("Source.md"))
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Document Preview Fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .sourceCorpus })
            let summary = try #require(vault.documents.first { $0.id.relativePath == "Source.md" })
            let snapshot = try await capabilities.documents.hydrate(summary)
            return Self(
                root: root, original: original, source: source,
                localAccessRecord: root.appendingPathComponent(
                    "ApplicationSupport/Triptychs/\(capabilities.id.uuidString)/attachment-access/indexed-attachments-v2.json"),
                store: store, documents: capabilities.documents,
                id: snapshot.id,
                target: .init(
                    noteID: try #require(snapshot.stableIdentity.resolvedID),
                    vaultID: snapshot.id.vaultID, relativePath: snapshot.id.relativePath))
        }
    }
}
