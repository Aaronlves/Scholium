import ScholiumContracts
import Combine
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

        let workspaceStore = makeTestWorkspaceStore()
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
        #expect(
            first.workspaceProjectionController !== second.workspaceProjectionController
        )

        first.presentationRouter.present(.transactionRecovery)
        #expect(first.presentationRouter.sheet?.id == "transaction-recovery")
        #expect(second.presentationRouter.sheet == nil)
        first.presentationRouter.dismissAll()

        let vaultID = UUID()
        let noteID = UUID()
        let sessionKey = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let firstSession = first.documentController.session(for: sessionKey)
        let secondSession = second.documentController.session(for: sessionKey)
        var firstWindowChangeCount = 0
        let firstWindowObservation = first.objectWillChange.sink {
            firstWindowChangeCount += 1
        }
        firstSession.editingSource = "first window exact bytes\n"
        #expect(firstWindowChangeCount == 0)
        #expect(firstSession !== secondSession)
        #expect(secondSession.editingSource.isEmpty)
        _ = firstWindowObservation

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
        first.discoveryController.failSearch(.failed("stale completion"), for: firstSearch)
        #expect(!first.discoveryController.search.isRunning)
        #expect(first.discoveryController.search.executionIssue == nil)
        #expect(second.discoveryController.search.isRunning)
        #expect(second.discoveryController.search.criteria.query == "reasons")
        second.discoveryController.failSearch(.failed("current completion"), for: secondSearch)
        #expect(second.discoveryController.search.executionIssue == .failed(
            "current completion"
        ))

        first.discoveryController.synchronizeLibrarySelection(
            workspaceSlot: .paperAnalysis,
            sourceScope: .library
        )
        #expect(first.discoveryController.library.sourceScope == .library)
        #expect(second.discoveryController.library.sourceScope == .library)

        first.pendingSourceLine = 17
        #expect(first.documentController.pendingSourceLine == 17)
        #expect(second.documentController.pendingSourceLine == nil)

        let mutationTarget = NoteMutationTarget(
            documentID: VaultQualifiedNoteID(
                vaultID: reference.vaultID,
                relativePath: reference.relativePath
            ),
            stableNoteID: noteID,
            revision: DocumentFingerprint(content: "# Agency\n")
        )
        first.documentController.requestFileOperation(.move(mutationTarget))
        #expect(first.noteFileRequest == .move(mutationTarget))
        #expect(first.presentationRouter.sheet?.id == "note-file-operation:move:\(mutationTarget.id)")
        #expect(second.noteFileRequest == nil)
        #expect(second.presentationRouter.sheet == nil)

        // Construction and window-local state changes do not activate a vault,
        // create a watcher, or publish derived runtime state.
        #expect(workspaceStore.workspaceSnapshots.isEmpty)

        first.documentController.removeAll()
        second.documentController.removeAll()
        await Task.yield()
    }

    @Test("Stopped document scrolling persists without invalidating the window model")
    func stoppedDocumentScrollingDoesNotInvalidateWindowModel() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent("Scholium-ScrollSession-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
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

        let store = makeTestWorkspaceStore()
        let window = WindowModel(workspaceStore: store)
        let sessionID = UUID()
        await window.restoreWindowSession(id: sessionID)
        try await waitUntil("the initial window session was persisted") {
            try await store.windowSession(id: sessionID) != nil
        }
        try await Task.sleep(for: .milliseconds(50))

        var invalidationCount = 0
        let observation = window.objectWillChange.sink {
            invalidationCount += 1
        }
        window.rememberScrollPosition(0.42, for: "Fixtures/Scroll.md")
        try await waitUntil("the stopped scroll position was persisted") {
            try await store.windowSession(id: sessionID)?
                .workspaceSession(for: .paperAnalysis)?
                .scrollPositions["Fixtures/Scroll.md"] == 0.42
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(invalidationCount == 0)
        observation.cancel()
    }

    @Test("Window close awaits its final session snapshot")
    func windowCloseAwaitsFinalSessionSnapshot() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent("Scholium-CloseSession-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
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

        let store = makeTestWorkspaceStore()
        let window = WindowModel(workspaceStore: store)
        let sessionID = UUID()
        await window.restoreWindowSession(id: sessionID)
        window.setDocumentTextScale(1.7)

        _ = try await window.prepareForWindowClose()

        let saved = try #require(try await store.windowSession(id: sessionID))
        #expect(saved.documentTextScale == 1.7)
    }

    @Test("Close preparation retains flush ownership until the window actually closes")
    func closePreparationRetainsFlushOwnership() async throws {
        let store = makeTestWorkspaceStore()
        let window = WindowModel(workspaceStore: store)
        window.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Active.md"
        )

        let token = UUID()
        var flushCount = 0
        window.registerEditorFlush(
            for: "Active.md",
            token: token,
            flush: { flushCount += 1 },
            captureForReconstruction: {}
        )

        // NoteContentView can disappear during an Inspector or hosting-view
        // reconstruction even though this same document remains selected.
        window.unregisterEditorFlush(token: token)
        window.searchController.begin(.general)

        await Task.yield()
        #expect(flushCount == 0)

        _ = try await window.prepareForWindowClose()
        #expect(flushCount == 1)

        // App termination can still be cancelled by another window. The same
        // open window must participate in a later close attempt.
        _ = try await window.prepareForWindowClose()
        #expect(flushCount == 2)

        window.finalizeWindowClose()
        _ = try await window.prepareForWindowClose()
        #expect(flushCount == 2)
    }

    @Test("Review requests do not enqueue a redundant Application-level editor flush")
    func reviewRequestDefersItsSingleFlushToTheDocumentSurface() async throws {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        window.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Active.md"
        )
        var flushCount = 0
        var captureCount = 0
        window.registerEditorFlush(
            for: "Active.md",
            token: UUID(),
            flush: { flushCount += 1 },
            captureForReconstruction: { captureCount += 1 }
        )

        window.requestDocumentMode(.read)

        #expect(window.requestPresentationMode == .read)
        #expect(flushCount == 0)
        #expect(captureCount == 0)
    }

    @Test("Replacing the current note flushes exact text once without serializing discarded editor state")
    func replacementNavigationSkipsReconstructionCapture() async throws {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        window.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Active.md"
        )
        var flushCount = 0
        var captureCount = 0
        window.registerEditorFlush(
            for: "Active.md",
            token: UUID(),
            flush: { flushCount += 1 },
            captureForReconstruction: { captureCount += 1 }
        )

        window.requestOpenNote("Missing fixture note.md")
        await window.waitForPendingDocumentTransitionsForTesting()

        #expect(flushCount == 1)
        #expect(captureCount == 0)
    }

    @Test("Triptych flush uses one aggregate registration per window")
    func triptychFlushDoesNotDoubleFlushOneWindow() async throws {
        let store = makeTestWorkspaceStore()
        let triptychID = UUID()
        let windowID = UUID()
        var aggregateFlushes = 0
        var selectedFlushes = 0
        store.registerEditorFlush(
            token: UUID(),
            triptychID: triptychID,
            windowID: windowID,
            relativePath: "",
            flush: { aggregateFlushes += 1 }
        )
        store.registerEditorFlush(
            token: UUID(),
            triptychID: triptychID,
            windowID: windowID,
            relativePath: "Current.md",
            flush: { selectedFlushes += 1 }
        )

        try await store.flushEditors(in: triptychID)

        #expect(aggregateFlushes == 1)
        #expect(selectedFlushes == 0)
    }

    @Test("A hanging content flush keeps the window retryable")
    func hangingContentFlushKeepsWindowRetryable() async throws {
        var policy = ScholiumLifecyclePolicy()
        policy.contentFlush = .milliseconds(30)
        let window = WindowModel(
            workspaceStore: makeTestWorkspaceStore(),
            lifecyclePolicy: policy
        )
        window.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Active.md"
        )
        let token = UUID()
        window.registerEditorFlush(
            for: "Active.md",
            token: token,
            flush: {
                await withUnsafeContinuation {
                    (_: UnsafeContinuation<Void, Never>) in
                }
            },
            captureForReconstruction: {}
        )

        do {
            _ = try await window.prepareForWindowClose()
            Issue.record("A hanging content flush incorrectly allowed close")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .timedOut(.contentFlush))
        } catch {
            Issue.record("Unexpected content deadline error: \(error)")
        }

        var retryFlushCount = 0
        window.registerEditorFlush(
            for: "Active.md",
            token: token,
            flush: { retryFlushCount += 1 },
            captureForReconstruction: {}
        )
        _ = try await window.prepareForWindowClose()
        #expect(retryFlushCount == 1)
    }

    @Test("Presentation persistence failure does not block a content-safe close")
    func presentationPersistenceDeadlineDoesNotBlockClose() async throws {
        let fileManager = FileManager.default
        let isolatedHome = fileManager.temporaryDirectory
            .appendingPathComponent("Scholium-PresentationDeadline-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
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

        var policy = ScholiumLifecyclePolicy()
        policy.presentationSnapshot = .milliseconds(30)
        let window = WindowModel(
            workspaceStore: makeTestWorkspaceStore(),
            lifecyclePolicy: policy,
            finalWindowSessionSaver: { _, _ in
                await withUnsafeContinuation {
                    (_: UnsafeContinuation<Void, Never>) in
                }
            }
        )
        await window.restoreWindowSession(id: UUID())
        window.documentController.selectUnavailableDocument(
            vaultID: UUID(),
            relativePath: "Active.md"
        )
        let token = UUID()
        var contentFlushCount = 0
        window.registerEditorFlush(
            for: "Active.md",
            token: token,
            flush: { contentFlushCount += 1 },
            captureForReconstruction: {}
        )

        let outcome = try await window.prepareForWindowClose()

        #expect(contentFlushCount == 1)
        #expect(outcome.presentationWarning != nil)
        #expect(window.windowSessionPersistenceError != nil)
        #expect(window.refreshStatusText == "Window state not saved")
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

        let workspaceStore = makeTestWorkspaceStore()
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
        secondWindow.presentationRouter.present(.transactionRecovery)
        #expect(secondWindow.presentationRouter.sheet?.id == "transaction-recovery")

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

    @Test("Agent bridge startup failure is retained without disabling the App runtime")
    func agentBridgeStartupFailureIsRetained() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/bridge-startup", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let support = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let occupiedNamespace = support.appendingPathComponent(
            "AgentBridge",
            isDirectory: true
        )
        let existing = try LocalAgentBridgeServer(
            applicationSupportURL: occupiedNamespace
        ) { _ in throw LocalAgentBridgeError.permissionDenied }
        defer { existing.stop() }
        let store = try WorkspaceStore(applicationSupportURL: support)
        #expect(store.localAgentBridge == nil)
        #expect(store.localAgentBridgeStartupFailure == .alreadyRunning)
        #expect(try await store.applicationRuntime.availableWorkspaces().isEmpty)
        await store.shutdownApplicationRuntime()
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

        let store = makeTestWorkspaceStore()
        let workspaceID = UUID()
        let initiallyConfigured = try await store.configureTriptychCapabilities(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: fixtureRoot,
            triptychID: workspaceID,
            triptychName: "Rebind Fixture"
        )
        let initialHandle = try await store.applicationRuntime.openWorkspace(id: workspaceID)
        let first = WindowModel(workspaceStore: store, requestedTriptychID: workspaceID)
        let second = WindowModel(workspaceStore: store, requestedTriptychID: workspaceID)
        await first.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)
        await second.refreshWorkspaceAssignment(preferredTriptychID: workspaceID)

        let firstInitial = try #require(first.windowWorkspaceController.activeCapabilities)
        let secondInitial = try #require(second.windowWorkspaceController.activeCapabilities)
        #expect(firstInitial.runtimeIdentity == initiallyConfigured.runtimeIdentity)
        #expect(secondInitial.runtimeIdentity == initiallyConfigured.runtimeIdentity)
        #expect(await initialHandle.events.subscriberCount == 1)

        first.presentationRouter.present(.transactionRecovery)
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

        let replacementTopics = fixtureRoot.appendingPathComponent(
            "Replacement Topics",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: replacementTopics,
            withIntermediateDirectories: true
        )
        try Data("# Replacement Topic\n\nA replacement topic.\n".utf8).write(
            to: replacementTopics.appendingPathComponent("Topic.md")
        )
        let replacement = try await store.configureTriptychCapabilities(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: replacementTopics,
            outputURL: works,
            portableContainerURL: fixtureRoot,
            triptychID: workspaceID,
            triptychName: "Rebind Fixture"
        )
        let replacementHandle = try await store.applicationRuntime.openWorkspace(id: workspaceID)
        let firstReplacement = try #require(
            first.windowWorkspaceController.activeCapabilities
        )
        let secondReplacement = try #require(
            second.windowWorkspaceController.activeCapabilities
        )
        #expect(replacement.runtimeIdentity != initiallyConfigured.runtimeIdentity)
        #expect(firstReplacement.runtimeIdentity == replacement.runtimeIdentity)
        #expect(secondReplacement.runtimeIdentity == replacement.runtimeIdentity)
        #expect(firstReplacement.runtimeIdentity == secondReplacement.runtimeIdentity)

        #expect(first.presentationRouter.sheet?.id == "transaction-recovery")
        #expect(second.presentationRouter.sheet == nil)
        #expect(first.discoveryController.search.criteria.query == "first-window")
        #expect(second.discoveryController.search.criteria.query == "second-window")
        #expect(first.documentController.session(for: sessionKey).editingSource == "first exact buffer")
        #expect(second.documentController.session(for: sessionKey).editingSource == "second exact buffer")

        #expect(try await first.documentController.workspaceSnapshots().count == 3)
        #expect(try await second.documentController.workspaceSnapshots().count == 3)
        #expect(try await first.discoveryController.discoverySnapshot().catalog.notes.count == 3)
        #expect(try await second.researchController.researchSnapshot().healthIssues.isEmpty)
        #expect(await initialHandle.events.subscriberCount == 0)
        #expect(await initialHandle.ownedBackgroundTaskCount == 0)
        #expect(await replacementHandle.events.subscriberCount == 1)

        await store.shutdownApplicationRuntime()
        #expect(await replacementHandle.events.subscriberCount == 0)
        #expect(await replacementHandle.ownedBackgroundTaskCount == 0)
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
        let duplicateTopicSource = "# Topic Shared\n\nA different note at the same relative path.\n"
        try Data(duplicateTopicSource.utf8).write(
            to: topics.appendingPathComponent("Shared.md")
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

        let store = makeTestWorkspaceStore()
        let configured = try await store.configureTriptychCapabilities(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: fixtureRoot,
            triptychName: "Live Multiwindow Fixture"
        )
        let workspaceID = configured.id
        let configuredHandle = try await store.applicationRuntime.openWorkspace(id: workspaceID)
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
        let topicsVault = try #require(configured.assignment.vault(for: .topicKnowledge))
        try await waitUntil("both windows loaded the Analysis vault") {
            firstWindow?.currentRegisteredVault?.id == analysesVault.id
                && secondWindow.currentRegisteredVault?.id == analysesVault.id
                && firstWindow?.noteIdentityByPath["Shared.md"] != nil
                && secondWindow.noteIdentityByPath["Shared.md"] != nil
        }

        firstWindow!.requestTriptychWorkspace(.topicKnowledge)
        firstWindow!.requestTriptychWorkspace(.paperAnalysis)
        try await Task.sleep(for: .milliseconds(100))
        #expect(firstWindow!.currentRegisteredVault?.id == analysesVault.id)
        #expect(firstWindow!.discoveryController.library.workspaceSlot == .paperAnalysis)

        let firstHandle = try #require(
            firstWindow!.windowWorkspaceController.activeCapabilities
        )
        let secondHandle = try #require(
            secondWindow.windowWorkspaceController.activeCapabilities
        )
        #expect(firstHandle.runtimeIdentity == configured.runtimeIdentity)
        #expect(secondHandle.runtimeIdentity == configured.runtimeIdentity)
        #expect(firstHandle.runtimeIdentity == secondHandle.runtimeIdentity)
        #expect(firstWindow!.documentController !== secondWindow.documentController)
        #expect(firstWindow!.presentationRouter !== secondWindow.presentationRouter)
        #expect(firstWindow!.discoveryController !== secondWindow.discoveryController)
        #expect(firstWindow!.researchController !== secondWindow.researchController)
        #expect(
            firstWindow!.workspaceProjectionController
                !== secondWindow.workspaceProjectionController
        )
        #expect(
            firstWindow!.researchAgentPermissionWindowController
                !== secondWindow.researchAgentPermissionWindowController
        )

        #expect(await configuredHandle.events.subscriberCount == 1)
        #expect(await configuredHandle.ownedBackgroundTaskCount > 0)
        #expect(await store.applicationRuntime.pooledVaultSubscriberCount(
            vaultID: analysesVault.id
        ) == 1)
        #expect(await store.applicationRuntime.pooledVaultOwnsNativeWatcher(
            vaultID: analysesVault.id
        ) == true)

        // These are the exact command-facing WindowModel properties used by
        // `ScholiumCommands` after SwiftUI resolves its focused scene value.
        // `FocusedValues` itself has no public initializer on the test SDK.
        firstWindow!.showTransactionRecovery = true
        #expect(firstWindow!.presentationRouter.sheet?.id == "transaction-recovery")
        #expect(secondWindow.presentationRouter.sheet == nil)
        secondWindow.showTransactionRecovery = true
        #expect(secondWindow.presentationRouter.sheet?.id == "transaction-recovery")
        #expect(firstWindow!.presentationRouter.sheet?.id == "transaction-recovery")
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
        firstWindow!.discoveryController.failSearch(.failed("late result"), for: firstSearch)
        #expect(firstSearch.id != secondSearch.id)
        #expect(!firstWindow!.discoveryController.search.isRunning)
        #expect(firstWindow!.discoveryController.search.executionIssue == nil)
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

        let revealGenerationBeforeOpen = firstWindow!.discoveryController
            .libraryRevealRequest?.generation ?? 0
        firstWindow!.openNote("Shared.md")
        secondWindow.openNote("Shared.md")
        firstWindow!.documentController.installOpenedDocument(
            original,
            vaultName: analysesVault.name,
            vaultRole: analysesVault.role
        )
        secondWindow.documentController.installOpenedDocument(
            original,
            vaultName: analysesVault.name,
            vaultRole: analysesVault.role
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
        try await waitUntil("the current Analysis reveal completed before manual Scope browsing") {
            guard let reveal = firstWindow?.discoveryController.libraryRevealRequest else {
                return false
            }
            return reveal.generation > revealGenerationBeforeOpen
                && reveal.relativePath == "Shared.md"
        }

        firstSession.preparePresentationMode(.livePreview)
        firstWindow!.rememberPresentationMode(.livePreview)
        firstSession.scrollFraction = 0.42
        firstWindow!.requestTriptychWorkspace(.topicKnowledge)
        try await waitUntil("the first window entered the retained Topics workspace") {
            firstWindow?.currentRegisteredVault?.id == topicsVault.id
                && firstWindow?.notes.contains(where: {
                    $0.relativePath == "Shared.md" && $0.rawContent == duplicateTopicSource
                }) == true
        }
        #expect(firstWindow!.shellState.selectedWorkspace == .topicKnowledge)
        #expect(firstWindow!.currentDocumentVaultID == nil)
        #expect(firstWindow!.selectedDocument == nil)
        #expect(firstWindow!.documentRevisions["Shared.md"] != original.fingerprint)
        #expect(firstWindow!.documentController.retainedSession(for: sessionKey) === firstSession)
        #expect(firstSession.presentationMode == .read)
        #expect(firstSession.pendingEditorMode == .livePreview)
        #expect(firstWindow!.currentPresentationMode == .livePreview)
        #expect(firstSession.scrollFraction == 0.42)

        firstWindow!.openNote("Shared.md")
        try await waitUntil("the Topic document opened in its own tab group") {
            firstWindow?.currentDocumentVaultID == topicsVault.id
        }
        let visibleReference = try #require(firstWindow!.currentDocumentDescriptor?.reference)
        let windowIDBeforeOpeningTab = firstWindow!.nativeWindowID
        let existingTabCount = firstWindow!.documentTabController.tabs(
            in: .topicKnowledge
        ).count
        firstWindow!.requestOpenNote(visibleReference, disposition: .newTab)
        try await waitUntil("the existing document tab was selected") {
            firstWindow?.documentTabController.selectedTab(in: .topicKnowledge)?
                .document.relativePath == "Shared.md"
        }
        #expect(firstWindow!.documentTabController.tabs(in: .topicKnowledge).count == existingTabCount)
        #expect(firstWindow!.nativeWindowID == windowIDBeforeOpeningTab)
        #expect(firstWindow!.documentTabController.selectedTab(in: .topicKnowledge)?.document.relativePath == "Shared.md")

        let visibleTarget = try #require(NoteMutationTarget(firstWindow!.currentNote!))
        #expect(visibleTarget.documentID.vaultID == topicsVault.id)
        let duplicatePath = "Duplicated Topic.md"
        _ = try await firstWindow!.duplicateNote(visibleTarget, to: duplicatePath)
        #expect(!fileManager.fileExists(atPath: analyses.appendingPathComponent(duplicatePath).path))
        #expect(fileManager.fileExists(atPath: topics.appendingPathComponent(duplicatePath).path))
        #expect(firstWindow!.currentDocumentVaultID == topicsVault.id)
        #expect(firstWindow!.selectedDocumentPath == duplicatePath)

        firstWindow!.requestTriptychWorkspace(.paperAnalysis)
        try await waitUntil("the first window restored the Analyses workspace") {
            firstWindow?.currentRegisteredVault?.id == analysesVault.id
                && firstWindow?.selectedDocument == originalID
        }
        #expect(firstWindow!.currentPresentationMode == .livePreview)
        #expect(firstWindow!.documentController.retainedSession(for: sessionKey) === firstSession)

        let cleanSource = originalSource + "\nCommitted from the first window.\n"
        let cleanCommit = try await firstWindow!.documentController.save(
            originalID,
            changeSet: .source(cleanSource),
            expectedRevision: original.fingerprint
        ).committedValue
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
        firstSession.beginEditing(in: .livePreview)
        firstSession.editingSource = exactDirtyBuffer
        firstSession.suppressAutosave = false
        let externalSource = "# Shared\n\nCommitted from the clean peer.\n"
        let externalCommit = try await secondWindow.documentController.save(
            originalID,
            changeSet: .source(externalSource),
            expectedRevision: cleanCommit.document.fingerprint
        ).committedValue
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
        firstSession.finishEditing()
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
        ).committedValue
        let renamedID = VaultQualifiedNoteID(
            vaultID: analysesVault.id,
            relativePath: renamedPath
        )
        #expect(moveCommit.destination == renamedID)
        try await waitUntil("both document controllers migrated the stable identity") {
            firstWindow?.documentController.activeDocument?.reference.relativePath == renamedPath
                && secondWindow.documentController.activeDocument?.reference.relativePath == renamedPath
        }
        try await waitUntil("both window shells migrated their selected document projections") {
            firstWindow?.selectedDocumentPath == renamedPath
                && secondWindow.selectedDocumentPath == renamedPath
        }
        try await waitUntil("both window shells migrated their stable identity projections") {
            firstWindow?.noteIdentityByPath[renamedPath] == stableNoteID
                && secondWindow.noteIdentityByPath[renamedPath] == stableNoteID
                && firstWindow?.noteIdentityByPath["Shared.md"] == nil
                && secondWindow.noteIdentityByPath["Shared.md"] == nil
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
        #expect(await configuredHandle.events.subscriberCount == 1)
        #expect(await configuredHandle.ownedBackgroundTaskCount > 0)
        #expect(await store.applicationRuntime.pooledVaultOwnsNativeWatcher(
            vaultID: analysesVault.id
        ) == true)
        #expect(secondWindow.discoveryController.search.isRunning)

        let survivingSource = "# Shared\n\nThe surviving window still owns live work.\n"
        let survivingCommit = try await secondWindow.documentController.save(
            renamedID,
            changeSet: .source(survivingSource),
            expectedRevision: moveCommit.committedRevision
        ).committedValue
        try await waitUntil("the surviving window received a later live commit") {
            secondSession.editingSource == survivingSource
                && secondSession.editingRevision == survivingCommit.document.fingerprint
        }

        try fileManager.removeItem(
            at: analyses.appendingPathComponent(renamedPath)
        )
        try await waitUntil("the clean externally deleted tab converged to no document") {
            secondWindow.documentTabController.tabs(in: .paperAnalysis).isEmpty
                && secondWindow.selectedDocument == nil
        }
        #expect(secondWindow.documentController.retainedSession(for: sessionKey) == nil)

        await store.shutdownApplicationRuntime()
        #expect(store.workspaceSnapshots.isEmpty)
        #expect(store.workspaceEvents.isEmpty)
        #expect(await configuredHandle.events.subscriberCount == 0)
        #expect(await configuredHandle.ownedBackgroundTaskCount == 0)
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

    @Test("Restore Access can remove an unavailable registration and return to unconfigured state")
    func restoreAccessRemovesUnavailableRegistration() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureRoot = repositoryRoot
            .appendingPathComponent(".build/app-unit-state", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let support = fixtureRoot.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let registry = support.appendingPathComponent("Workspace", isDirectory: true)
        let triptychRoot = fixtureRoot.appendingPathComponent("Triptych", isDirectory: true)
        let analyses = triptychRoot.appendingPathComponent("Analyses", isDirectory: true)
        let topics = triptychRoot.appendingPathComponent("Topics", isDirectory: true)
        let works = triptychRoot.appendingPathComponent("Works", isDirectory: true)
        for directory in [support, registry, analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let retainedSource = topics.appendingPathComponent("Retained.md")
        let retainedBytes = Data("research source remains unchanged".utf8)
        try retainedBytes.write(to: retainedSource)
        let seedingRuntime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: support,
            workspaceRegistryStorageURL: registry
        )))
        let assignment = try await seedingRuntime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: triptychRoot,
            triptychName: "Unavailable"
        ).assignment
        await seedingRuntime.shutdown()
        let manifestURL = triptychRoot.appendingPathComponent(".scholium/manifest.json")
        let unsupportedManifest = Data(#"{"schemaVersion":0,"preserve":true}"#.utf8)
        try unsupportedManifest.write(to: manifestURL)
        try FileManager.default.removeItem(at: analyses)

        let store = try WorkspaceStore(applicationSupportURL: support)
        let window = WindowModel(workspaceStore: store)
        await window.refreshWorkspaceAssignment()

        #expect(window.workspaceAssignment?.id == assignment.id)
        #expect(window.workspaceAccessRecovery?.kind == .vault)
        #expect(window.activeTriptychServicesID == nil)
        #expect(window.canRemoveUnavailableTriptychRegistration)

        try await window.removeUnavailableTriptychRegistration()

        #expect(window.workspaceAssignment == nil)
        #expect(window.workspaceAccessRecovery == nil)
        #expect(window.registeredTriptychs.isEmpty)
        #expect(try await store.registeredTriptychs().isEmpty)
        #expect(try Data(contentsOf: retainedSource) == retainedBytes)
        #expect(try Data(contentsOf: manifestURL) == unsupportedManifest)
        await store.shutdownApplicationRuntime()
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

}

private enum CompositionRootTestError: Error {
    case missingStoredReference(String)
    case conditionTimedOut(String)
}
