import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Saved window session restoration", .serialized)
@MainActor
struct WindowSessionRestorationTests {
    @Test("A registration read failure in a new window cannot authorize setup and retries the same route")
    func newWindowRegistrationReadFailure() async throws {
        let fixture = WindowSessionRestorationFixture()
        defer { fixture.remove() }
        _ = try await fixture.seedSession(selectedRole: .paperAnalysis)
        let id = UUID()
        try await fixture.withStore { store in
            let originalRegistry = try Data(contentsOf: fixture.registryURL)
            let damagedRegistry = Data("{ synthetic invalid registry".utf8)
            try damagedRegistry.write(to: fixture.registryURL)
            let window = WindowModel(workspaceStore: store, nativeWindowID: id)
            defer { window.windowCloseCoordinator.finalize() }

            await window.restoreWindowSession(id: id)
            #expect(window.shellState.hasCompletedInitialRestore)
            #expect(!window.didRestoreWindowSession)
            #expect(!window.windowWorkspaceController.state.needsRegistration)
            #expect(window.windowWorkspaceController.state.accessRecovery == nil)
            #expect(window.vaultConfig == nil)
            #expect(window.vaultError != nil)
            #expect(try Data(contentsOf: fixture.registryURL) == damagedRegistry)
            #expect(!FileManager.default.fileExists(atPath: fixture.sessionURL(id: id).path))

            try originalRegistry.write(to: fixture.registryURL)
            await window.restoreWindowSession(id: id)
            #expect(window.didRestoreWindowSession)
            #expect(window.vaultConfig != nil)
            #expect(window.vaultError == nil)
            #expect(!window.windowWorkspaceController.state.needsRegistration)
            #expect(window.shellState.selectedWorkspace == .paperAnalysis)
            #expect(window.documentTabController.tabs.isEmpty)
            fixture.assertNotesPreserved()
        }
    }

    @Test(
        "Saved Topics and Works open their own Library immediately and retain presentation without Note tabs",
        arguments: [WorkspaceVaultSlot.topicKnowledge, .output]
    )
    func savedRoleIsTheInitialUsableVault(_ role: WorkspaceVaultSlot) async throws {
        let fixture = WindowSessionRestorationFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedSession(selectedRole: role)
        let triptychID = try #require(saved.triptychID)
        let registryBytes = try Data(contentsOf: fixture.registryURL)

        try await fixture.withStore { store in
            let window = WindowModel(workspaceStore: store, nativeWindowID: saved.id)
            var initialPhase: WorkspaceSnapshotPhase?
            let observation = store.$workspaceSnapshots.sink { snapshots in
                if initialPhase == nil {
                    initialPhase = snapshots[triptychID]?.phase
                }
            }
            defer { observation.cancel() }
            defer { window.windowCloseCoordinator.finalize() }

            await window.restoreWindowSession(id: saved.id)

            #expect(initialPhase == .opening(availableVault: role))
            assertRestoredPresentation(window, saved: saved)
            #expect(window.notes.map(\.relativePath) == [fixture.noteName(for: role)])
            #expect(window.vaultError == nil)
            #expect(window.windowWorkspaceController.state.accessRecovery == nil)
            #expect(!window.windowWorkspaceController.state.needsRegistration)
            #expect(!window.isLoading)
            let registryPreserved = try Data(contentsOf: fixture.registryURL) == registryBytes
            #expect(registryPreserved)
            fixture.assertNotesPreserved()

            _ = try await window.windowCloseCoordinator.prepare()
            let persisted = try #require(try await store.windowSession(id: saved.id))
            #expect(persisted.selectedWorkspace == role)
            #expect(persisted.documentMode == saved.documentMode)
            #expect(persisted.libraryVisible == saved.libraryVisible)
            #expect(persisted.inspectorVisible == saved.inspectorVisible)
            #expect(persisted.documentTextScale == saved.documentTextScale)
            #expect(persisted.openDocuments.isEmpty)
            #expect(persisted.selectedDocument == nil)
        }
    }

    @Test("Unavailable saved Works preserves exact session through failed restoration and close preparation, then retries the same window")
    func unavailableWorksRetainsSessionAndRetriesSameWindow() async throws {
        let fixture = WindowSessionRestorationFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedSession(selectedRole: .output)
        let savedBytes = try Data(contentsOf: fixture.sessionURL(id: saved.id))
        let registryBytes = try Data(contentsOf: fixture.registryURL)
        try fixture.makeWorksUnavailable()

        try await fixture.withStore { store in
            let window = WindowModel(workspaceStore: store, nativeWindowID: saved.id)
            defer { window.windowCloseCoordinator.finalize() }
            await window.restoreWindowSession(id: saved.id)

            assertIncompleteRestoration(window, saved: saved, fixture: fixture)
            try await assertStoredSessionPreserved(store, saved: saved, bytes: savedBytes, fixture: fixture)
            // Ordinary persistence requests and close preparation must not
            // replace an unrestored layout with the window's default state.
            window.persistWindowSessionNow()
            let close = try await window.windowCloseCoordinator.prepare()
            #expect(close.presentationWarning == nil)
            #expect(!window.didRestoreWindowSession)
            try await assertStoredSessionPreserved(store, saved: saved, bytes: savedBytes, fixture: fixture)

            try fixture.restoreExactWorksFolder()
            await window.restoreWindowSession(id: saved.id)

            assertRestoredPresentation(window, saved: saved)
            #expect(window.notes.map(\.relativePath) == [fixture.noteName(for: .output)])
            #expect(window.windowWorkspaceController.state.accessRecovery == nil)
            #expect(window.vaultError == nil)
            let registryPreserved = try Data(contentsOf: fixture.registryURL) == registryBytes
            #expect(registryPreserved)
            fixture.assertNotesPreserved()
        }
    }

    @Test("Closing an incomplete restored window preserves its saved layout for reopening with the same session ID")
    func closingFailedRestorationPreservesSessionForReopen() async throws {
        let fixture = WindowSessionRestorationFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedSession(selectedRole: .output)
        let savedBytes = try Data(contentsOf: fixture.sessionURL(id: saved.id))
        try fixture.makeWorksUnavailable()

        try await fixture.withStore { store in
            let window = WindowModel(workspaceStore: store, nativeWindowID: saved.id)
            defer { window.windowCloseCoordinator.finalize() }
            await window.restoreWindowSession(id: saved.id)
            assertIncompleteRestoration(window, saved: saved, fixture: fixture)
            _ = try await window.windowCloseCoordinator.prepare()
            window.windowCloseCoordinator.finalize()
            try await assertStoredSessionPreserved(store, saved: saved, bytes: savedBytes, fixture: fixture)
        }

        try fixture.restoreExactWorksFolder()
        try await fixture.withStore { store in
            let window = WindowModel(workspaceStore: store, nativeWindowID: saved.id)
            defer { window.windowCloseCoordinator.finalize() }
            await window.restoreWindowSession(id: saved.id)
            assertRestoredPresentation(window, saved: saved)
            #expect(window.notes.map(\.relativePath) == [fixture.noteName(for: .output)])
            fixture.assertNotesPreserved()
        }
    }

    @Test("Opening defers background Changes until the complete projection exposes an unseen Works edit")
    func pendingChangesWaitForCompleteProjection() async throws {
        let fixture = WindowSessionRestorationFixture()
        defer { fixture.remove() }
        let saved = try await fixture.seedSession(selectedRole: .paperAnalysis)
        let triptychID = try #require(saved.triptychID)
        let worksVaultID = try #require(saved.workspaceSession(for: .output)?.vaultID)
        let worksURL = fixture.vaultURL(for: .output).appendingPathComponent(fixture.noteName(for: .output))
        let originalWorks = try Data(contentsOf: worksURL)
        let editedWorks = Data("\u{FEFF}# Work\r\n\r\nUnseen synthetic edit after the complete baseline was saved.".utf8)
        try editedWorks.write(to: worksURL, options: .atomic)
        let registryBytes = try Data(contentsOf: fixture.registryURL)

        try await fixture.withStore { store in
            let window = WindowModel(workspaceStore: store, nativeWindowID: saved.id)
            defer { window.windowCloseCoordinator.finalize() }
            await window.restoreWindowSession(id: saved.id)

            assertRestoredPresentation(window, saved: saved)
            #expect(window.notes.map(\.relativePath) == [fixture.noteName(for: .paperAnalysis)])
            #expect(window.workspaceProjectionController.snapshotPhase == .opening(availableVault: .paperAnalysis))
            #expect(window.researchController.pendingChanges == nil)
            #expect(window.researchController.pendingChangesError == nil)
            let opening = try #require(store.workspaceSnapshots[triptychID])
            #expect(opening.phase == .opening(availableVault: .paperAnalysis))

            // Release the existing presentation boundary. The unseen Works
            // change must be discovered by complete projection, then loaded
            // into Changes without an explicit Changes-sheet request.
            let handle = try await store.applicationRuntime.openWorkspace(id: triptychID)
            await handle.openingPresentationDidComplete()
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while ContinuousClock.now < deadline,
                window.workspaceProjectionController.snapshotPhase?.isComplete != true
                    || window.researchController.pendingChanges == nil
            {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(window.workspaceProjectionController.snapshotPhase?.isComplete == true)
            let complete = try #require(store.workspaceSnapshots[triptychID])
            #expect(complete.phase.isComplete)
            #expect(complete.vaults.reduce(0) { $0 + $1.documents.count } == 3)
            // Reading complete source does not acknowledge review or require
            // a Changes revision bump. Completeness itself wakes the loader.
            #expect(complete.documentChangesGeneration == opening.documentChangesGeneration)
            let pending = try #require(window.researchController.pendingChanges)
            #expect(pending.count == 1)
            let unseenWorks = try #require(
                pending.first {
                    $0.vaultID == worksVaultID && $0.relativePath == fixture.noteName(for: .output)
                })
            #expect(unseenWorks.role == .draftProject)
            #expect(unseenWorks.baselineState == .known)
            #expect(unseenWorks.startingRevision == DocumentFingerprint(data: originalWorks))
            #expect(unseenWorks.endingRevision == DocumentFingerprint(data: editedWorks))
            #expect(window.researchController.pendingChangesError == nil)
            #expect(window.documentController.selectedDocument == nil)
            #expect(window.documentTabController.tabs.isEmpty)
            let editedBytesPreserved = try Data(contentsOf: worksURL) == editedWorks
            let registryPreserved = try Data(contentsOf: fixture.registryURL) == registryBytes
            #expect(editedBytesPreserved)
            #expect(registryPreserved)
            for role in [WorkspaceVaultSlot.paperAnalysis, .topicKnowledge] {
                let sourcePreserved =
                    try Data(contentsOf: fixture.vaultURL(for: role).appendingPathComponent(fixture.noteName(for: role)))
                    == fixture.sourceBytes(for: role)
                #expect(sourcePreserved)
            }
        }
    }

    private func assertRestoredPresentation(_ window: WindowModel, saved: WindowSessionSnapshot) {
        #expect(window.windowSessionID == saved.id)
        #expect(window.didRestoreWindowSession)
        #expect(!window.isRestoringWindowSession)
        #expect(window.shellState.hasCompletedInitialRestore)
        #expect(window.workspaceAssignment?.id == saved.triptychID)
        #expect(window.currentRegisteredVault?.id == saved.workspaceSession(for: saved.selectedWorkspace)?.vaultID)
        #expect(window.shellState.selectedWorkspace == saved.selectedWorkspace)
        #expect(window.currentPresentationMode.rawValue == saved.documentMode)
        #expect(window.sidebarVisible == saved.libraryVisible)
        #expect(window.researchInspectorVisible == saved.inspectorVisible)
        #expect(window.documentTextScale == saved.documentTextScale)
        for role in WorkspaceVaultSlot.allCases {
            #expect(window.shellState.inspectorMode(for: role).rawValue == saved.workspaceSession(for: role)?.inspectorMode)
        }
        #expect(window.documentController.selectedDocument == nil)
        #expect(window.documentTabController.tabs.isEmpty)
    }

    private func assertIncompleteRestoration(
        _ window: WindowModel, saved: WindowSessionSnapshot, fixture: WindowSessionRestorationFixture
    ) {
        #expect(window.windowSessionID == saved.id)
        #expect(!window.didRestoreWindowSession)
        #expect(!window.isRestoringWindowSession)
        // The shell may present the completed opening attempt's recovery;
        // durable presentation restoration remains incomplete.
        #expect(window.shellState.hasCompletedInitialRestore)
        #expect(window.workspaceAssignment?.id == saved.triptychID)
        #expect(!window.windowWorkspaceController.state.needsRegistration)
        #expect(window.windowWorkspaceController.state.accessRecovery?.kind == .vault)
        #expect(window.windowWorkspaceController.state.accessRecovery?.expectedPath == fixture.vaultURL(for: .output).path)
        #expect(window.documentController.selectedDocument == nil)
        #expect(window.documentTabController.tabs.isEmpty)
    }

    private func assertStoredSessionPreserved(
        _ store: WorkspaceStore, saved: WindowSessionSnapshot, bytes: Data, fixture: WindowSessionRestorationFixture
    ) async throws {
        #expect(try await store.windowSession(id: saved.id) == saved)
        let exactBytesPreserved = try Data(contentsOf: fixture.sessionURL(id: saved.id)) == bytes
        #expect(exactBytesPreserved)
    }
}

@MainActor
private struct WindowSessionRestorationFixture {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/window-session-restoration-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)

    var triptychURL: URL { root.appendingPathComponent("Triptych", isDirectory: true) }
    var supportURL: URL { root.appendingPathComponent("ApplicationSupport", isDirectory: true) }
    var registryURL: URL { supportURL.appendingPathComponent("Workspace/workspace-registration-v3.json") }
    var unavailableWorksURL: URL { root.appendingPathComponent("Unavailable Works", isDirectory: true) }

    func sessionURL(id: UUID) -> URL {
        supportURL.appendingPathComponent("Window Sessions/\(id.uuidString).json")
    }

    func vaultURL(for role: WorkspaceVaultSlot) -> URL {
        triptychURL.appendingPathComponent(role.displayName, isDirectory: true)
    }

    func noteName(for role: WorkspaceVaultSlot) -> String {
        switch role {
        case .paperAnalysis: "Analysis.md"
        case .topicKnowledge: "Topic.md"
        case .output: "Work.md"
        }
    }

    func sourceBytes(for role: WorkspaceVaultSlot) -> Data {
        switch role {
        case .paperAnalysis: Data("# Analysis\n\nSynthetic source only.\n".utf8)
        case .topicKnowledge: Data("# Topic\n\nSynthetic topic only.\n".utf8)
        case .output: Data("\u{FEFF}# Work\r\n\r\nSynthetic exact source without a final newline.".utf8)
        }
    }

    func withStore(_ operation: @MainActor (WorkspaceStore) async throws -> Void) async throws {
        let store = try WorkspaceStore(applicationSupportURL: supportURL)
        do {
            try await operation(store)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    func seedSession(selectedRole: WorkspaceVaultSlot) async throws -> WindowSessionSnapshot {
        // The ordinary-launch contract deliberately has no QA fixture route
        // or launch-only Note request, and these tests never create an app.
        try #require(ScholiumRuntimeIsolation.fixtureRootURL() == nil)
        try #require(ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"] == nil)
        for role in WorkspaceVaultSlot.allCases {
            let vault = vaultURL(for: role)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            try sourceBytes(for: role).write(to: vault.appendingPathComponent(noteName(for: role)))
        }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: supportURL,
                    workspaceRegistryStorageURL: supportURL.appendingPathComponent("Workspace")
                )))
        do {
            let configured = try await runtime.configureTriptych(
                paperAnalysisURL: vaultURL(for: .paperAnalysis),
                topicKnowledgeURL: vaultURL(for: .topicKnowledge),
                outputURL: vaultURL(for: .output),
                portableContainerURL: triptychURL,
                triptychName: "Session restoration fixture"
            )
            let assignment = configured.assignment
            let selectedVault = try #require(assignment.vault(for: selectedRole))
            let selectedNote = VaultQualifiedNoteID(vaultID: selectedVault.id, relativePath: noteName(for: selectedRole))
            let saved = WindowSessionSnapshot(
                triptychID: assignment.id, selectedWorkspace: selectedRole,
                openDocuments: [selectedNote], selectedDocument: selectedNote,
                workspaceSessions: WorkspaceVaultSlot.allCases.map { role in
                    WindowWorkspaceSessionSnapshot(
                        workspace: role, vaultID: assignment.vault(for: role)?.id,
                        documentPresentations: role == selectedRole
                            ? [noteName(for: role): WindowDocumentPresentationSnapshot(scrollFraction: 0.37)] : [:],
                        inspectorMode: role == .paperAnalysis ? "links" : "related"
                    )
                },
                documentMode: "source", libraryVisible: false,
                inspectorVisible: true, documentTextScale: 1.7
            )
            try await runtime.saveWindowSession(saved)
            await runtime.shutdown()
            return saved
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    func makeWorksUnavailable() throws {
        // Moving the exact disposable folder preserves its inode and source
        // bytes. Its bookmark may follow the move, but live access rejects a
        // canonical path different from the registration's expected path.
        try FileManager.default.moveItem(at: vaultURL(for: .output), to: unavailableWorksURL)
    }

    func restoreExactWorksFolder() throws {
        try FileManager.default.moveItem(at: unavailableWorksURL, to: vaultURL(for: .output))
    }

    func assertNotesPreserved() {
        for role in WorkspaceVaultSlot.allCases {
            let exactBytesPreserved =
                (try? Data(contentsOf: vaultURL(for: role).appendingPathComponent(noteName(for: role))))
                == sourceBytes(for: role)
            #expect(exactBytesPreserved)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
