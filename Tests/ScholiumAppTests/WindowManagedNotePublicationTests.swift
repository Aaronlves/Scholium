import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Managed Note creation publication", .serialized) @MainActor
struct WindowManagedNotePublicationTests {
    enum DelayedEvent: String, Sendable {
        case citation, failedRefresh

        func event(snapshot: WorkspaceSnapshot, vaultID: UUID, generation: UInt64) -> WorkspaceEvent {
            switch self {
            case .citation:
                return .citationAuthorityInvalidated(
                    .init(
                        generation: generation, snapshot: snapshot,
                        derivedRefreshStatus: .current(.init(snapshot: snapshot))))
            case .failedRefresh:
                return .derivedStateChanged(
                    .init(
                        generation: generation,
                        status: .failed(
                            .init(
                                reason: "Synthetic failed refresh retaining the pre-creation snapshot.",
                                affectedVaultIDs: [vaultID], lastKnownGood: .init(snapshot: snapshot))),
                        discovery: snapshot.discovery, snapshot: snapshot))
            }
        }
    }

    enum DeletionDelivery: String, Sendable {
        case snapshot, coalescedCitation, coalescedConfiguration
    }

    // Keep real asynchronous fixture deliveries below these explicitly ordered
    // events; their source snapshots are real, while delivery is controlled.
    private static let injectedGeneration = UInt64.max - 4

    @Test(
        "An older projection delivered during opening cannot hide a committed new Note",
        arguments: [DelayedEvent.citation, .failedRefresh])
    func delayedProjectionBeforeOpen(_ delayed: DelayedEvent) async throws {
        let fixture = try await CreationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let (capabilities, before, created) = try await createNote(in: fixture)
            let reference = try recordCreation(created, in: fixture.window)
            let event = delayed.event(
                snapshot: before, vaultID: created.id.vaultID, generation: Self.injectedGeneration)
            var injected = false
            try await fixture.window.activateWorkspaceReference(
                reference, tabActivation: .place(.replaceSelected),
                managedCreationBodyStartUTF16: created.document.bodyUTF16Offset,
                committedSnapshot: created.sourceAheadSnapshot,
                validateSource: {
                    try #require(fixture.window.workspaceProjectionController.canReceive(event, runtimeIdentity: capabilities.runtimeIdentity))
                    fixture.window.receiveWorkspaceEvents([capabilities.id: event])
                    injected = true
                })
            #expect(injected)
            try expectCreatedNoteOpen(created, in: fixture)
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test(
        "An older projection delivered after opening preserves the new Edit session and Library membership",
        arguments: [DelayedEvent.citation, .failedRefresh])
    func delayedProjectionAfterOpen(_ delayed: DelayedEvent) async throws {
        let fixture = try await CreationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let (capabilities, before, created) = try await createNote(in: fixture)
            let reference = try recordCreation(created, in: fixture.window)
            try await fixture.window.activateWorkspaceReference(
                reference, tabActivation: .place(.replaceSelected),
                managedCreationBodyStartUTF16: created.document.bodyUTF16Offset,
                committedSnapshot: created.sourceAheadSnapshot)
            try expectCreatedNoteOpen(created, in: fixture)
            let selected = fixture.window.documentController.selectedDocument
            let event = delayed.event(
                snapshot: before, vaultID: created.id.vaultID, generation: Self.injectedGeneration)
            try #require(fixture.window.workspaceProjectionController.canReceive(event, runtimeIdentity: capabilities.runtimeIdentity))
            fixture.window.receiveWorkspaceEvents([capabilities.id: event])
            #expect(fixture.window.documentController.selectedDocument == selected)
            try expectCreatedNoteOpen(created, in: fixture)
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test(
        "A complete rebuilt inventory after actual deletion closes a clean new Note through snapshot or coalesced metadata delivery",
        arguments: [DeletionDelivery.snapshot, .coalescedCitation, .coalescedConfiguration])
    func actualDeletionRemainsAuthoritative(_ delivery: DeletionDelivery) async throws {
        let fixture = try await CreationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let (capabilities, _, created) = try await createNote(in: fixture, freezingGeneration: Self.injectedGeneration - 1)
            let reference = try recordCreation(created, in: fixture.window)
            try await fixture.window.activateWorkspaceReference(
                reference, tabActivation: .place(.replaceSelected),
                managedCreationBodyStartUTF16: created.document.bodyUTF16Offset,
                committedSnapshot: created.sourceAheadSnapshot)
            try expectCreatedNoteOpen(created, in: fixture)
            let published = try await capabilities.discovery.refresh()
            try #require(published.phase.isComplete)
            try #require(published.vaults.flatMap(\.documents).contains { $0.id == created.id })
            if delivery == .snapshot {
                fixture.window.receiveWorkspaceEvents([
                    capabilities.id: .snapshot(.init(generation: Self.injectedGeneration, snapshot: published))
                ])
            }
            let key = DocumentSessionKey(vaultID: created.id.vaultID, noteID: try #require(created.stableIdentity.resolvedID))
            let session = try #require(fixture.window.documentController.retainedSession(for: key))
            #expect(!session.hasUnsavedChanges)

            let sourceURL = fixture.works.appendingPathComponent(created.id.relativePath)
            try FileManager.default.removeItem(at: sourceURL)
            let deleted = try await capabilities.discovery.refresh()
            try #require(deleted.phase.isComplete)
            #expect(!deleted.vaults.flatMap(\.documents).contains { $0.id == created.id })
            // In the coalesced arms no created inventory was delivered to the
            // window. The metadata event alone carries the newer complete
            // inventory proving that the formerly source-ahead Note is gone.
            #expect(fixture.window.documentController.selectedDocument?.sessionKey == key)
            let deletionEvent: WorkspaceEvent
            switch delivery {
            case .snapshot:
                deletionEvent = .snapshot(.init(generation: Self.injectedGeneration + 1, snapshot: deleted))
            case .coalescedCitation:
                deletionEvent = .citationAuthorityInvalidated(
                    .init(
                        generation: Self.injectedGeneration + 1, snapshot: deleted,
                        derivedRefreshStatus: .current(.init(snapshot: deleted))))
            case .coalescedConfiguration:
                deletionEvent = .researchConfigurationInvalidated(
                    .init(generation: Self.injectedGeneration + 1, snapshot: deleted))
            }
            try #require(fixture.window.workspaceProjectionController.canReceive(deletionEvent, runtimeIdentity: capabilities.runtimeIdentity))
            fixture.window.receiveWorkspaceEvents([capabilities.id: deletionEvent])
            await fixture.window.waitForDocumentTransitions()

            #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
            #expect(!fixture.window.notes.contains { $0.summary.id == created.id })
            #expect(fixture.window.documentController.selectedDocument?.sessionKey != key)
            #expect(!fixture.window.documentTabController.tabs.contains { $0.document.sessionKey == key })
            #expect(fixture.window.documentController.retainedDeletedDocumentPath == nil)
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("An expired creation presentation preserves the selected Document while keeping the committed Note in Library")
    func expiredCreationPresentationDoesNotNavigate() async throws {
        let fixture = try await CreationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let window = fixture.window
            let selected = try #require(window.documentController.selectedDocument)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let vault = try #require(window.currentRegisteredVault)
            let outcome = try await capabilities.libraryMutations.createUntitledNote(inVault: vault.id, folderRelativePath: nil)
            let created = outcome.committedValue
            let key = DocumentSessionKey(vaultID: created.id.vaultID, noteID: try #require(created.stableIdentity.resolvedID))
            await window.publishCommittedNoteCreation(outcome, isCurrent: { false })
            #expect(window.documentController.selectedDocument == selected)
            #expect(window.currentRegisteredVault?.id == vault.id)
            #expect(!window.documentTabController.tabs.contains { $0.document.sessionKey == key })
            let listed = try #require(window.notes.first { $0.summary.id == created.id })
            #expect(listed.summary.stableIdentity.resolvedID == key.noteID)
            #expect(listed.summary.fingerprint == created.document.fingerprint)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent(created.id.relativePath)) == created.document.sourceBytes)
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    private func createNote(
        in fixture: CreationFixture, freezingGeneration: UInt64? = nil
    ) async throws -> (WindowWorkspaceCapabilities, WorkspaceSnapshot, WorkspaceManagedNoteCommit) {
        let capabilities = try #require(fixture.window.windowWorkspaceController.activeCapabilities)
        let before = try #require(fixture.store.snapshot(for: capabilities.runtimeIdentity))
        try #require(before.phase.isComplete)
        if let freezingGeneration {
            // Freeze delivery while the fixture still precedes creation so
            // asynchronous real events cannot preempt the manual event oracle.
            fixture.window.receiveWorkspaceEvents([
                capabilities.id: .snapshot(.init(generation: freezingGeneration, snapshot: before))
            ])
        }
        let vault = try #require(fixture.window.currentRegisteredVault)
        let outcome = try await capabilities.libraryMutations.createUntitledNote(inVault: vault.id, folderRelativePath: nil)
        let created = outcome.committedValue
        _ = try #require(created.stableIdentity.resolvedID)
        #expect(created.id.vaultID == vault.id)
        #expect(created.vaultRole == .draftProject)
        #expect(created.document.relativePath.utf8.elementsEqual(created.id.relativePath.utf8))
        #expect(!before.vaults.flatMap(\.documents).contains { $0.id == created.id })
        #expect(try Data(contentsOf: fixture.works.appendingPathComponent(created.id.relativePath)) == created.document.sourceBytes)
        return (capabilities, before, created)
    }

    private func recordCreation(_ created: WorkspaceManagedNoteCommit, in window: WindowModel) throws -> VaultNoteReference {
        let vault = try #require(
            window.workspaceProjectionController.recordCommittedNoteCreation(
                created, visibleVaultID: window.currentRegisteredVault?.id,
                visibleSourceScope: window.noteSourceScope))
        let noteID = try #require(created.stableIdentity.resolvedID)
        return .init(
            vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
            relativePath: created.id.relativePath, stableNoteID: noteID.uuidString)
    }

    private func expectCreatedNoteOpen(_ created: WorkspaceManagedNoteCommit, in fixture: CreationFixture) throws {
        let window = fixture.window
        let noteID = try #require(created.stableIdentity.resolvedID)
        let selected = try #require(window.documentController.selectedDocument)
        let descriptor = try #require(selected.workspaceDescriptor)
        #expect(descriptor.sessionKey == DocumentSessionKey(vaultID: created.id.vaultID, noteID: noteID))
        #expect(descriptor.reference.relativePath.utf8.elementsEqual(created.id.relativePath.utf8))
        #expect(window.documentTabController.selectedTab?.document == selected)
        #expect(window.documentController.currentPresentationMode == .livePreview)
        let session = try #require(window.documentController.retainedSession(for: descriptor.sessionKey))
        #expect(session.isEditing)
        #expect(session.presentationMode == .livePreview)
        #expect(session.activeEditorMode == .livePreview)
        #expect(session.managedCreationBodyStartUTF16 == created.document.bodyUTF16Offset)
        #expect(Data(session.editingSource.utf8) == created.document.sourceBytes)
        #expect(Data(session.originalEditingSource.utf8) == created.document.sourceBytes)
        #expect(session.editingRevision == created.document.fingerprint)
        let installed = try #require(window.documentController.snapshots[descriptor.sessionKey])
        #expect(installed.document.sourceBytes == created.document.sourceBytes)
        #expect(installed.fingerprint == created.document.fingerprint)
        let listed = try #require(window.notes.first { $0.summary.id == created.id })
        #expect(listed.summary.stableIdentity.resolvedID == noteID)
        #expect(listed.relativePath.utf8.elementsEqual(created.id.relativePath.utf8))
        #expect(listed.summary.fingerprint == created.document.fingerprint)
        #expect(try Data(contentsOf: fixture.works.appendingPathComponent(created.id.relativePath)) == created.document.sourceBytes)
    }

    @MainActor
    private struct CreationFixture {
        let root: URL
        let works: URL
        let store: WorkspaceStore
        let window: WindowModel

        static func make() async throws -> Self {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/managed-note-publication/\(UUID())", isDirectory: true)
            let triptych = root.appendingPathComponent("Triptych", isDirectory: true)
            let analyses = triptych.appendingPathComponent("Analyses", isDirectory: true)
            let topics = triptych.appendingPathComponent("Topics", isDirectory: true)
            let works = triptych.appendingPathComponent("Works", isDirectory: true)
            for directory in [analyses, topics, works] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data("\u{FEFF}Origin source 中文 😀 e\u{301}。\r\n".utf8).write(to: works.appendingPathComponent("Origin.md"))
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            do {
                let configured = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Managed creation fixture")
                let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
                try await window.openWorkspaceVault(.output)
                window.documentController.rememberPresentationMode(.read)
                try await window.openNote("Origin.md")
                return Self(root: root, works: works, store: store, window: window)
            } catch {
                await store.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }
}
