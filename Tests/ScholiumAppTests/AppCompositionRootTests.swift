import ScholiumContracts
import Darwin
import Foundation
@testable import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("App composition root", .serialized)
@MainActor
struct AppCompositionRootTests {
    @Test("Two windows share application services and isolate window state")
    func twoWindowComposition() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent("Scholium-AppComposition-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: isolatedHome,
            withIntermediateDirectories: true
        )
        let previousHome = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"]
        setenv("SCHOLIUM_HOME", isolatedHome.path, 1)
        defer {
            if let previousHome {
                setenv("SCHOLIUM_HOME", previousHome, 1)
            } else {
                unsetenv("SCHOLIUM_HOME")
            }
            try? fileManager.removeItem(at: isolatedHome)
        }

        let workspaceStore = WorkspaceStore()
        let first = WindowModel(workspaceStore: workspaceStore)
        let second = WindowModel(workspaceStore: workspaceStore)

        let firstWorkspaceStore: WorkspaceStore = try storedReference(
            named: "workspaceStore",
            in: first
        )
        let secondWorkspaceStore: WorkspaceStore = try storedReference(
            named: "workspaceStore",
            in: second
        )
        #expect(ObjectIdentifier(firstWorkspaceStore) == ObjectIdentifier(workspaceStore))
        #expect(ObjectIdentifier(secondWorkspaceStore) == ObjectIdentifier(workspaceStore))
        #expect(
            ObjectIdentifier(firstWorkspaceStore.applicationRuntime)
                == ObjectIdentifier(workspaceStore.applicationRuntime)
        )
        #expect(
            ObjectIdentifier(secondWorkspaceStore.applicationRuntime)
                == ObjectIdentifier(workspaceStore.applicationRuntime)
        )

        #expect(ObjectIdentifier(first.cssSnippetStore) == ObjectIdentifier(workspaceStore.cssSnippetStore))
        #expect(ObjectIdentifier(second.cssSnippetStore) == ObjectIdentifier(workspaceStore.cssSnippetStore))
        #expect(ObjectIdentifier(first.zoteroBridge) == ObjectIdentifier(workspaceStore.zoteroBridge))
        #expect(ObjectIdentifier(second.zoteroBridge) == ObjectIdentifier(workspaceStore.zoteroBridge))
        #expect(workspaceStore.applicationSupportURL == isolatedHome.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        ))

        #expect(first.windowSessionID != second.windowSessionID)
        #expect(first.presentationRouter !== second.presentationRouter)
        #expect(first.discoveryController !== second.discoveryController)
        #expect(first.documentController !== second.documentController)
        #expect(first.researchController !== second.researchController)

        first.presentationRouter.present(.quickOpen)
        #expect(first.presentationRouter.sheet?.id == "quick-open")
        #expect(second.presentationRouter.sheet == nil)
        first.presentationRouter.dismissAll()

        let vaultID = UUID()
        let noteID = UUID()
        let sessionKey = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let firstSession = first.documentController.session(for: sessionKey)
        let secondSession = second.documentController.session(for: sessionKey)
        firstSession.editingSource = "first window exact bytes\n"
        #expect(firstSession !== secondSession)
        #expect(secondSession.editingSource.isEmpty)

        let reference = VaultNoteReference(
            vaultID: vaultID,
            vaultName: "Fixture Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Topics/Agency.md",
            stableNoteID: noteID.uuidString.lowercased()
        )
        let descriptor = WindowDocumentDescriptor(
            sessionKey: sessionKey,
            reference: reference
        )
        let firstControllerSession = first.documentController.session(for: descriptor)
        let secondControllerSession = second.documentController.session(for: descriptor)
        #expect(firstControllerSession === firstSession)
        #expect(secondControllerSession === secondSession)
        firstControllerSession.editingSource = "first controller buffer"
        #expect(firstControllerSession !== secondControllerSession)
        #expect(secondControllerSession.editingSource.isEmpty)

        let firstSearch = first.discoveryController.beginSearch(SearchWorkspaceState(
            query: "agency",
            scope: .triptych
        ))
        let secondSearch = second.discoveryController.beginSearch(SearchWorkspaceState(
            query: "reasons",
            scope: .thisNote
        ))
        #expect(firstSearch.id != secondSearch.id)
        first.discoveryController.cancelSearch()
        first.discoveryController.failSearch("stale completion", for: firstSearch)
        #expect(!first.discoveryController.search.isRunning)
        #expect(first.discoveryController.search.errorMessage == nil)
        #expect(second.discoveryController.search.isRunning)
        #expect(second.discoveryController.search.criteria.query == "reasons")
        second.discoveryController.failSearch("current completion", for: secondSearch)
        #expect(second.discoveryController.search.errorMessage == "current completion")

        first.discoveryController.selectLocationScope(.trash)
        first.researchController.showNoteHistory(true)
        #expect(first.discoveryController.library.locationScope == .trash)
        #expect(second.discoveryController.library.locationScope == .workspace)
        #expect(first.researchController.inspector.showsNoteHistory)
        #expect(!second.researchController.inspector.showsNoteHistory)

        first.documentController.requestLifecycle(.move(reference.relativePath))
        #expect(first.noteLifecycleRequest == .move("Topics/Agency.md"))
        #expect(first.presentationRouter.sheet?.id == "lifecycle:move:Topics/Agency.md")
        #expect(second.noteLifecycleRequest == nil)
        #expect(second.presentationRouter.sheet == nil)

        // Construction and window-local state changes do not activate a vault,
        // create a watcher, or publish derived runtime state.
        #expect(workspaceStore.workspaceSnapshots.isEmpty)
        #expect(workspaceStore.workspaceEventGenerations.isEmpty)

        first.documentController.removeAll()
        second.documentController.removeAll()
        await Task.yield()
    }

    @Test("Removing one window does not shut down the shared Application runtime")
    func windowRemovalPreservesApplicationRuntime() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent("Scholium-RuntimeLifetime-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: isolatedHome,
            withIntermediateDirectories: true
        )
        let previousHome = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"]
        setenv("SCHOLIUM_HOME", isolatedHome.path, 1)
        defer {
            if let previousHome {
                setenv("SCHOLIUM_HOME", previousHome, 1)
            } else {
                unsetenv("SCHOLIUM_HOME")
            }
            try? fileManager.removeItem(at: isolatedHome)
        }

        let workspaceStore = WorkspaceStore()
        var firstWindow: WindowModel? = WindowModel(workspaceStore: workspaceStore)
        let secondWindow = WindowModel(workspaceStore: workspaceStore)
        let firstStore: WorkspaceStore = try storedReference(
            named: "workspaceStore",
            in: firstWindow!
        )
        let secondStore: WorkspaceStore = try storedReference(
            named: "workspaceStore",
            in: secondWindow
        )
        #expect(
            ObjectIdentifier(firstStore.applicationRuntime)
                == ObjectIdentifier(secondStore.applicationRuntime)
        )

        weak let releasedWindow = firstWindow
        firstWindow = nil
        for _ in 0..<20 where releasedWindow != nil {
            await Task.yield()
        }
        #expect(releasedWindow == nil)

        // The Application runtime belongs to WorkspaceStore, not either
        // window. Removing one borrower therefore leaves it usable by the
        // surviving window and any later window.
        #expect(try await workspaceStore.applicationRuntime.availableWorkspaces().isEmpty)
        secondWindow.presentationRouter.present(.quickOpen)
        #expect(secondWindow.presentationRouter.sheet?.id == "quick-open")

        await workspaceStore.shutdownApplicationRuntime()
        do {
            _ = try await workspaceStore.applicationRuntime.availableWorkspaces()
            Issue.record("An explicitly shut-down Application runtime remained usable.")
        } catch let error as ScholiumApplicationError {
            guard case .runtimeShutDown = error else {
                Issue.record("Unexpected Application runtime error: \(error)")
                return
            }
        }
    }

    @Test("Two existing windows adopt one replacement and preserve local state")
    func twoWindowsAdoptRuntimeReplacement() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent(
                "Scholium-RebindComposition-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        let fixtureRoot = isolatedHome.appendingPathComponent("Fixture", isDirectory: true)
        let analyses = fixtureRoot.appendingPathComponent("Analyses", isDirectory: true)
        let topics = fixtureRoot.appendingPathComponent("Topics", isDirectory: true)
        let works = fixtureRoot.appendingPathComponent("Works", isDirectory: true)
        for directory in [analyses, topics, works] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("# Analysis\n\nExact source.\n".utf8).write(
            to: analyses.appendingPathComponent("Analysis.md")
        )
        try Data("# Topic\n\nA topic.\n".utf8).write(
            to: topics.appendingPathComponent("Topic.md")
        )
        try Data("# Work\n\nA work.\n".utf8).write(
            to: works.appendingPathComponent("Work.md")
        )
        let previousHome = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"]
        setenv("SCHOLIUM_HOME", isolatedHome.path, 1)
        defer {
            if let previousHome {
                setenv("SCHOLIUM_HOME", previousHome, 1)
            } else {
                unsetenv("SCHOLIUM_HOME")
            }
            try? fileManager.removeItem(at: isolatedHome)
        }

        let store = WorkspaceStore()
        let workspaceID = UUID()
        let initiallyConfigured = try await store.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: fixtureRoot,
            triptychID: workspaceID,
            triptychName: "Rebind Fixture"
        )
        let first = WindowModel(workspaceStore: store, requestedTriptychID: workspaceID)
        let second = WindowModel(workspaceStore: store, requestedTriptychID: workspaceID)
        await first.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)
        await second.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)

        let firstInitial: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: first
        )
        let secondInitial: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: second
        )
        #expect(firstInitial.runtimeIdentity == initiallyConfigured.runtimeIdentity)
        #expect(secondInitial.runtimeIdentity == initiallyConfigured.runtimeIdentity)
        #expect(await initiallyConfigured.events.subscriberCount == 1)

        first.presentationRouter.present(.quickOpen)
        first.discoveryController.beginSearch(SearchWorkspaceState(
            query: "first-window",
            scope: .triptych
        ))
        second.discoveryController.beginSearch(SearchWorkspaceState(
            query: "second-window",
            scope: .thisNote
        ))
        let sessionKey = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        first.documentController.session(for: sessionKey).editingSource = "first exact buffer"
        second.documentController.session(for: sessionKey).editingSource = "second exact buffer"

        let replacement = try await store.reloadTriptych(id: workspaceID)
        let firstReplacement: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: first
        )
        let secondReplacement: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: second
        )
        #expect(replacement !== initiallyConfigured)
        #expect(firstReplacement.runtimeIdentity == replacement.runtimeIdentity)
        #expect(secondReplacement.runtimeIdentity == replacement.runtimeIdentity)
        #expect(firstReplacement.runtimeIdentity == secondReplacement.runtimeIdentity)

        #expect(first.presentationRouter.sheet?.id == "quick-open")
        #expect(second.presentationRouter.sheet == nil)
        #expect(first.discoveryController.search.criteria.query == "first-window")
        #expect(second.discoveryController.search.criteria.query == "second-window")
        #expect(first.documentController.session(for: sessionKey).editingSource == "first exact buffer")
        #expect(second.documentController.session(for: sessionKey).editingSource == "second exact buffer")

        #expect(try await first.documentController.workspaceSnapshots().count == 3)
        #expect(try await second.documentController.workspaceSnapshots().count == 3)
        #expect(try await first.discoveryController.discoverySnapshot().catalog.notes.count == 3)
        #expect(try await second.researchController.researchSnapshot().healthIssues.isEmpty)
        #expect(await initiallyConfigured.events.subscriberCount == 0)
        #expect(await initiallyConfigured.ownedBackgroundTaskCount == 0)
        #expect(await replacement.events.subscriberCount == 1)

        await store.shutdownApplicationRuntime()
        #expect(await replacement.events.subscriberCount == 0)
        #expect(await replacement.ownedBackgroundTaskCount == 0)
    }

    @Test("Two live windows converge safely while retaining independent sessions")
    func twoLiveWindowsConvergeSafely() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent(
                "Scholium-LiveMultiwindow-\(UUID().uuidString)",
                isDirectory: true
            )
        let fixtureRoot = isolatedHome.appendingPathComponent("Fixture", isDirectory: true)
        let analyses = fixtureRoot.appendingPathComponent("Analyses", isDirectory: true)
        let topics = fixtureRoot.appendingPathComponent("Topics", isDirectory: true)
        let works = fixtureRoot.appendingPathComponent("Works", isDirectory: true)
        for directory in [isolatedHome, fixtureRoot, analyses, topics, works] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let originalSource = "# Shared\n\nOriginal exact source.\n"
        try Data(originalSource.utf8).write(
            to: analyses.appendingPathComponent("Shared.md")
        )
        try Data("# Topic\n\nA related topic.\n".utf8).write(
            to: topics.appendingPathComponent("Topic.md")
        )
        try Data("# Work\n\nA draft work.\n".utf8).write(
            to: works.appendingPathComponent("Work.md")
        )

        let previousHome = ProcessInfo.processInfo.environment["SCHOLIUM_HOME"]
        setenv("SCHOLIUM_HOME", isolatedHome.path, 1)
        defer {
            if let previousHome {
                setenv("SCHOLIUM_HOME", previousHome, 1)
            } else {
                unsetenv("SCHOLIUM_HOME")
            }
            try? fileManager.removeItem(at: isolatedHome)
        }

        let store = WorkspaceStore()
        let configured = try await store.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: fixtureRoot,
            triptychName: "Live Multiwindow Fixture"
        )
        let workspaceID = configured.id
        var firstWindow: WindowModel? = WindowModel(
            workspaceStore: store,
            requestedTriptychID: workspaceID
        )
        let secondWindow = WindowModel(
            workspaceStore: store,
            requestedTriptychID: workspaceID
        )
        await firstWindow!.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)
        await secondWindow.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)
        try await firstWindow!.openWorkspaceVault(.paperAnalysis)
        try await secondWindow.openWorkspaceVault(.paperAnalysis)

        let analysesVault = try #require(configured.assignment.vault(for: .paperAnalysis))
        try await waitUntil("both windows loaded the Analysis vault") {
            firstWindow?.currentRegisteredVault?.id == analysesVault.id
                && secondWindow.currentRegisteredVault?.id == analysesVault.id
                && firstWindow?.noteIdentityByPath["Shared.md"] != nil
                && secondWindow.noteIdentityByPath["Shared.md"] != nil
        }

        let firstHandle: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: firstWindow!
        )
        let secondHandle: WindowWorkspaceCapabilities = try storedOptionalValue(
            named: "activeWorkspaceCapabilities",
            in: secondWindow
        )
        #expect(firstHandle.runtimeIdentity == configured.runtimeIdentity)
        #expect(secondHandle.runtimeIdentity == configured.runtimeIdentity)
        #expect(firstHandle.runtimeIdentity == secondHandle.runtimeIdentity)
        #expect(firstWindow!.documentController !== secondWindow.documentController)
        #expect(firstWindow!.presentationRouter !== secondWindow.presentationRouter)
        #expect(firstWindow!.discoveryController !== secondWindow.discoveryController)
        #expect(firstWindow!.researchController !== secondWindow.researchController)

        #expect(await configured.events.subscriberCount == 1)
        #expect(await configured.ownedBackgroundTaskCount > 0)
        #expect(await store.applicationRuntime.pooledVaultSubscriberCount(
            vaultID: analysesVault.id
        ) == 1)
        #expect(await store.applicationRuntime.pooledVaultOwnsNativeWatcher(
            vaultID: analysesVault.id
        ) == true)

        // These are the exact command-facing WindowModel properties used by
        // `ScholiumCommands` after SwiftUI resolves its focused scene value.
        // `FocusedValues` itself has no public initializer on the test SDK.
        firstWindow!.showQuickOpen = true
        #expect(firstWindow!.presentationRouter.sheet?.id == "quick-open")
        #expect(secondWindow.presentationRouter.sheet == nil)
        secondWindow.showCreateCheckpoint = true
        #expect(secondWindow.presentationRouter.sheet?.id == "create-checkpoint")
        #expect(firstWindow!.presentationRouter.sheet?.id == "quick-open")
        firstWindow!.presentationRouter.dismissAll()
        secondWindow.presentationRouter.dismissAll()

        let firstSearch = firstWindow!.discoveryController.beginSearch(SearchWorkspaceState(
            query: "first-window cancellation",
            scope: .triptych
        ))
        let secondSearch = secondWindow.discoveryController.beginSearch(SearchWorkspaceState(
            query: "second-window survives",
            scope: .triptych
        ))
        firstWindow!.discoveryController.cancelSearch()
        firstWindow!.discoveryController.failSearch("late result", for: firstSearch)
        #expect(firstSearch.id != secondSearch.id)
        #expect(!firstWindow!.discoveryController.search.isRunning)
        #expect(firstWindow!.discoveryController.search.errorMessage == nil)
        #expect(secondWindow.discoveryController.search.isRunning)

        let originalID = VaultQualifiedNoteID(
            vaultID: analysesVault.id,
            relativePath: "Shared.md"
        )
        let maybeOriginal = try await firstWindow!.documentController.noteSnapshot(originalID)
        let original = try #require(maybeOriginal)
        let stableNoteID = try #require(original.stableIdentity.resolvedID)
        let sessionKey = DocumentSessionKey(
            vaultID: analysesVault.id,
            noteID: stableNoteID
        )

        firstWindow!.openNote("Shared.md")
        secondWindow.openNote("Shared.md")
        firstWindow!.documentController.installOpenedDocument(
            original,
            vaultName: analysesVault.name,
            vaultRole: analysesVault.role,
            inNewTab: false
        )
        secondWindow.documentController.installOpenedDocument(
            original,
            vaultName: analysesVault.name,
            vaultRole: analysesVault.role,
            inNewTab: false
        )
        let firstSession = try #require(
            firstWindow!.documentController.retainedSession(for: sessionKey)
        )
        let secondSession = try #require(
            secondWindow.documentController.retainedSession(for: sessionKey)
        )
        #expect(firstSession !== secondSession)
        #expect(firstSession.editingSource == originalSource)
        #expect(secondSession.editingSource == originalSource)

        let cleanSource = "# Shared\n\nCommitted from the first window.\n"
        let cleanCommit = try await firstWindow!.documentController.save(
            originalID,
            changeSet: .source(cleanSource),
            expectedRevision: original.fingerprint
        )
        try await waitUntil("a clean peer converged to the committed source") {
            firstSession.editingSource == cleanSource
                && firstSession.editingRevision == cleanCommit.document.fingerprint
                && secondSession.editingSource == cleanSource
                && secondSession.editingRevision == cleanCommit.document.fingerprint
        }
        #expect(firstSession.conflict == nil)
        #expect(secondSession.conflict == nil)

        let exactDirtyBuffer = "\u{FEFF}# Shared\r\n\r\nUncommitted exact editor bytes.\r\n"
        firstSession.suppressAutosave = true
        firstSession.isEditing = true
        firstSession.editingSource = exactDirtyBuffer
        firstSession.suppressAutosave = false
        let externalSource = "# Shared\n\nCommitted from the clean peer.\n"
        let externalCommit = try await secondWindow.documentController.save(
            originalID,
            changeSet: .source(externalSource),
            expectedRevision: cleanCommit.document.fingerprint
        )
        try await waitUntil("the dirty peer entered Conflict without losing its buffer") {
            firstSession.conflict?.diskRevision == externalCommit.document.fingerprint
                && secondSession.editingRevision == externalCommit.document.fingerprint
        }
        #expect(firstSession.editingSource == exactDirtyBuffer)
        #expect(firstSession.conflict?.editorSource == exactDirtyBuffer)
        #expect(firstSession.conflict?.diskSource == externalSource)
        #expect(firstSession.conflict?.baseRevision == cleanCommit.document.fingerprint)
        #expect(secondSession.editingSource == externalSource)
        #expect(secondSession.conflict == nil)

        // Model the researcher accepting the published disk revision before
        // testing path migration. This changes only the first window's local
        // editor state; both windows continue borrowing the same capability.
        firstSession.suppressAutosave = true
        firstSession.isEditing = false
        firstSession.editingSource = externalSource
        firstSession.originalEditingSource = externalSource
        firstSession.editingRevision = externalCommit.document.fingerprint
        firstSession.conflict = nil
        firstSession.editError = nil
        firstSession.suppressAutosave = false

        let firstSessionIdentity = ObjectIdentifier(firstSession)
        let secondSessionIdentity = ObjectIdentifier(secondSession)
        let renamedPath = "Renamed/Shared.md"
        let moveCommit = try await secondWindow.documentController.move(
            originalID,
            to: renamedPath,
            expectedRevision: externalCommit.document.fingerprint
        )
        let renamedID = VaultQualifiedNoteID(
            vaultID: analysesVault.id,
            relativePath: renamedPath
        )
        #expect(moveCommit.destination == renamedID)
        try await waitUntil("both document controllers migrated the stable identity") {
            firstWindow?.documentController.activeDocument?.reference.relativePath == renamedPath
                && secondWindow.documentController.activeDocument?.reference.relativePath == renamedPath
        }
        try await waitUntil("both window shells migrated their independent tab projections") {
            firstWindow?.openTabs == [renamedPath]
                && secondWindow.openTabs == [renamedPath]
        }
        #expect(ObjectIdentifier(firstWindow!.documentController.session(for: sessionKey)) == firstSessionIdentity)
        #expect(ObjectIdentifier(secondWindow.documentController.session(for: sessionKey)) == secondSessionIdentity)
        #expect(firstWindow!.noteIdentityByPath[renamedPath] == stableNoteID)
        #expect(secondWindow.noteIdentityByPath[renamedPath] == stableNoteID)
        #expect(firstWindow!.noteIdentityByPath["Shared.md"] == nil)
        #expect(secondWindow.noteIdentityByPath["Shared.md"] == nil)

        weak let releasedWindow = firstWindow
        firstWindow = nil
        try await waitUntil("the closed window released its independent lifetime") {
            releasedWindow == nil
        }
        #expect(await configured.events.subscriberCount == 1)
        #expect(await configured.ownedBackgroundTaskCount > 0)
        #expect(await store.applicationRuntime.pooledVaultOwnsNativeWatcher(
            vaultID: analysesVault.id
        ) == true)
        #expect(secondWindow.discoveryController.search.isRunning)

        let survivingSource = "# Shared\n\nThe surviving window still owns live work.\n"
        let survivingCommit = try await secondWindow.documentController.save(
            renamedID,
            changeSet: .source(survivingSource),
            expectedRevision: moveCommit.committedRevision
        )
        try await waitUntil("the surviving window received a later live commit") {
            secondSession.editingSource == survivingSource
                && secondSession.editingRevision == survivingCommit.document.fingerprint
        }

        await store.shutdownApplicationRuntime()
        #expect(store.workspaceSnapshots.isEmpty)
        #expect(store.workspaceEvents.isEmpty)
        #expect(store.workspaceEventGenerations.isEmpty)
        #expect(await configured.events.subscriberCount == 0)
        #expect(await configured.ownedBackgroundTaskCount == 0)
        do {
            _ = try await store.applicationRuntime.availableWorkspaces()
            Issue.record("The explicitly shut-down live runtime remained usable.")
        } catch let error as ScholiumApplicationError {
            guard case .runtimeShutDown = error else {
                Issue.record("Unexpected Application runtime error: \(error)")
                return
            }
        }
    }

    private func waitUntil(
        _ description: String,
        attempts: Int = 240,
        condition: @MainActor () async throws -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw CompositionRootTestError.conditionTimedOut(description)
    }

    private func storedReference<T: AnyObject>(
        named name: String,
        in owner: Any
    ) throws -> T {
        guard let value = Mirror(reflecting: owner).children.first(where: {
            $0.label == name
        })?.value as? T else {
            throw CompositionRootTestError.missingStoredReference(name)
        }
        return value
    }

    private func storedOptionalValue<T>(named name: String, in owner: Any) throws -> T {
        guard let optional = Mirror(reflecting: owner).children.first(where: {
            $0.label == name
        })?.value,
        let value = Mirror(reflecting: optional).children.first?.value as? T else {
            throw CompositionRootTestError.missingStoredReference(name)
        }
        return value
    }
}

private enum CompositionRootTestError: Error {
    case missingStoredReference(String)
    case conditionTimedOut(String)
}
