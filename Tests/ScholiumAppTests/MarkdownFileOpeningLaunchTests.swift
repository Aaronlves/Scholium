import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Markdown file launch routing", .serialized)
struct MarkdownFileOpeningLaunchTests {
    @Test("Initial Bootstrap cannot route before AppKit establishes the launch intent")
    func bootstrapWaitsForLaunchIntent() {
        let opening = MarkdownFileOpeningController()
        #expect(opening.launchPresentation == .awaitingLaunch)
        #expect(!opening.consumeLaunchBootstrapSuppression())
        opening.finishLaunching(isDefaultLaunch: true)
        #expect(opening.launchPresentation == .defaultWorkspace)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Managed routing respects the Note inventory and leaves attachment originals external")
    func inventoryRoutingEligibility() {
        let root = URL(fileURLWithPath: "/nonexistent-scholium-routing-fixture/Topics")
        for excluded in ["Attachments/Original.md", ".scholium/state.md", "Nested/.hidden/Original.md", "Outside.markdown", "../Outside.md"] {
            #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent(excluded), in: root) == nil)
        }
        #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent("Nested/Note.md"), in: root) == "Nested/Note.md")
        #expect(
            MarkdownFileOpeningController.managedMarkdownRelativePath(at: root.appendingPathComponent("Nested/Attachments/Note.md"), in: root)
                == "Nested/Attachments/Note.md")
    }

    @Test("Filesystem-equivalent spellings keep registered Notes on their guarded Triptych route")
    func filesystemSpellingPreservesManagedRouting() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let parent = root.appendingPathComponent("SyntheticTriptych", isDirectory: true)
            let folders = ["Analyses", "Topics", "Works"].map { parent.appendingPathComponent($0, isDirectory: true) }
            for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            let nested = folders[1].appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            let noteURL = nested.appendingPathComponent("Café.md")
            let bytes = Data("# Registered source\r\n".utf8)
            try bytes.write(to: noteURL)
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            let assignmentID: UUID
            let vaultID: UUID
            do {
                let capabilities = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: folders[0], topicKnowledgeURL: folders[1], outputURL: folders[2],
                    portableContainerURL: parent, triptychName: "Synthetic Triptych"
                )
                assignmentID = capabilities.id
                vaultID = try #require((try await store.registeredTriptychs()).first?.vault(for: .topicKnowledge)?.id)
                await store.shutdownApplicationRuntime()
            } catch {
                await store.shutdownApplicationRuntime()
                throw error
            }

            let caseSensitive = try #require(
                noteURL.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames)
            let alternate = parent.appendingPathComponent("topics/nested/cafe\u{301}.md")
            if caseSensitive {
                // On a case-sensitive volume this really is another file and
                // must remain external, even with identical source bytes.
                try FileManager.default.createDirectory(at: alternate.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: alternate)
            }
            opening.requestOpen([alternate])
            try await waitUntil { !workspaceRoutes.values.isEmpty || !externalRoutes.values.isEmpty }
            if caseSensitive {
                #expect(workspaceRoutes.values.isEmpty)
                #expect(externalRoutes.values.first?.fileURL == alternate)
            } else {
                let route = try #require(workspaceRoutes.values.first)
                #expect(route.triptychID == assignmentID)
                #expect(route.initialDocument?.vaultID == vaultID)
                #expect(route.initialDocument?.relativePath == "Nested/Café.md")
                #expect(externalRoutes.values.isEmpty)
            }
            #expect(try Data(contentsOf: noteURL) == bytes)

            let attachment = folders[1].appendingPathComponent("Attachments/Original.md")
            try FileManager.default.createDirectory(at: attachment.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: attachment)
            let selectedAttachment = caseSensitive ? attachment : parent.appendingPathComponent("topics/attachments/original.md")
            #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: selectedAttachment, in: folders[1]) == nil)

            let link = root.appendingPathComponent("OutsideLink.md")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: noteURL)
            #expect(MarkdownFileOpeningController.managedMarkdownRelativePath(at: link, in: folders[1]) == nil)
        }
    }

    @Test("A queued launch file suppresses only the initial Bootstrap, even when it attaches after launch finishes")
    func pendingLaunchSurvivesUntilBootstrapConsumesIt() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([file("Initial.md")])
        opening.finishLaunching(isDefaultLaunch: true)

        #expect(opening.launchPresentation == .requestedScene)
        #expect(opening.consumeLaunchBootstrapSuppression())
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("A file launch suppresses Bootstrap when the file event arrives after didFinishLaunching")
    func lateInitialFileDoesNotOpenWorkspace() {
        let delegate = ScholiumApplicationDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification,
                userInfo: [NSApplication.launchIsDefaultUserInfoKey: false]
            )
        )
        #expect(delegate.markdownFiles.launchPresentation == .requestedScene)
        delegate.application(NSApplication.shared, open: [file("Late.md")])
        #expect(delegate.markdownFiles.consumeLaunchBootstrapSuppression())
        #expect(!delegate.markdownFiles.consumeLaunchBootstrapSuppression())
    }

    @Test("A restored-scene launch suppresses only its redundant initial Bootstrap")
    func restoredSceneDoesNotCreateDefaultWorkspace() {
        let opening = MarkdownFileOpeningController()
        opening.finishLaunching(isDefaultLaunch: false)
        #expect(opening.launchPresentation == .requestedScene)
        #expect(opening.consumeLaunchBootstrapSuppression())
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Several initial file events cannot rearm suppression after the launch Bootstrap consumes it")
    func multipleLaunchFilesConsumeOnlyOneBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([file("First.md")])
        #expect(opening.consumeLaunchBootstrapSuppression())

        opening.requestOpen([file("Second.markdown"), file("Third.md")])

        #expect(opening.launchPresentation == .requestedScene)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Opening a file in a running app cannot suppress a later ordinary Bootstrap or Dock reopen")
    func warmOpeningDoesNotSuppressBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.finishLaunching(isDefaultLaunch: true)
        opening.requestOpen([file("Later.md")])

        #expect(opening.launchPresentation == .defaultWorkspace)
        #expect(!opening.consumeLaunchBootstrapSuppression())
    }

    @Test("Empty events and rejected termination-time events never acquire launch suppression")
    func nonadmittedRequestsDoNotSuppressBootstrap() {
        let opening = MarkdownFileOpeningController()
        opening.requestOpen([])
        #expect(!opening.consumeLaunchBootstrapSuppression())
        opening.prepareTermination()
        opening.requestOpen([file("Rejected.md")])
        #expect(!opening.consumeLaunchBootstrapSuppression())
        opening.cancelTermination()
        opening.requestOpen([file("Admitted.md")])
        #expect(opening.consumeLaunchBootstrapSuppression())
    }

    @Test("External files route independently and leave an existing workspace lifecycle untouched")
    func externalOpeningPreservesWorkspace() async throws {
        try await withRouting { opening, registry, root, externalRoutes, workspaceRoutes in
            let workspaceID = UUID()
            var workspaceFlushes = 0
            registry.register(id: workspaceID) { workspaceFlushes += 1 }
            defer { registry.unregister(id: workspaceID) }
            registry.markAttached(id: workspaceID)
            registry.markReady(id: workspaceID)
            opening.finishLaunching(isDefaultLaunch: true)
            let first = root.appendingPathComponent("First.md")
            let second = root.appendingPathComponent("Second.markdown")
            let bytes = Data("\u{FEFF}# Independent reader\r\n".utf8)
            try bytes.write(to: first)
            try bytes.write(to: second)
            opening.requestOpen([first, first, second])
            try await waitUntil { externalRoutes.values.count == 2 }

            #expect(externalRoutes.values.map(\.fileURL) == [first, second])
            #expect(workspaceRoutes.values.isEmpty)
            #expect(workspaceFlushes == 0)
            #expect(registry.hasRegisteredWindows)
            try await registry.waitUntilReady(id: workspaceID)
            #expect(opening.launchPresentation == .defaultWorkspace)
            #expect(try Data(contentsOf: first) == bytes)
            #expect(try Data(contentsOf: second) == bytes)
        }
    }

    @Test("Reopening a retained external reader reveals its session, and a closed reader opens fresh")
    func externalRevealAndCloseStayIndependent() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let url = root.appendingPathComponent("Outside.md")
            let bytes = Data("# Outside\r\n".utf8)
            try bytes.write(to: url)
            let model = ExternalMarkdownWindowModel(url: url)
            await model.open()
            let retainedIdentity = model.documentID
            let retainedEditor = model.editorSession
            let registry = ExternalMarkdownWindowRegistry.shared
            registry.register(model)
            defer {
                model.close()
                registry.unregister(model)
            }
            opening.finishLaunching(isDefaultLaunch: true)
            opening.requestOpen([url])
            // Follow the serial request queue with another distinct file. Its
            // presentation proves that the preceding reveal finished.
            let other = root.appendingPathComponent("Other.md")
            try bytes.write(to: other)
            opening.requestOpen([other])
            try await waitUntil { externalRoutes.values.count == 1 }
            #expect(externalRoutes.values.first?.fileURL == other)
            #expect(model.documentID == retainedIdentity)
            #expect(model.editorSession === retainedEditor)
            #expect(workspaceRoutes.values.isEmpty)

            model.close()
            opening.requestOpen([url])
            try await waitUntil { externalRoutes.values.count == 2 }
            #expect(externalRoutes.values.last?.fileURL == url)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Registry failure does not block an external .markdown file or an already retained reader")
    func independentReaderSurvivesRegistryFailure() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let warmup = root.appendingPathComponent("Warmup.markdown")
            try Data("# Warmup".utf8).write(to: warmup)
            opening.requestOpen([warmup])
            try await waitUntil { externalRoutes.values.count == 1 }
            let original = root.appendingPathComponent("Retained.md")
            let bytes = Data("# Retained outside Triptych\r\n".utf8)
            try bytes.write(to: original)
            let model = ExternalMarkdownWindowModel(url: original)
            await model.open()
            let identity = model.documentID
            let registry = ExternalMarkdownWindowRegistry.shared
            registry.register(model)
            defer {
                model.close()
                registry.unregister(model)
            }
            let registration = root.appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
            try FileManager.default.createDirectory(at: registration.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("deliberately malformed synthetic registry".utf8).write(to: registration)
            let next = root.appendingPathComponent("Independent.markdown")
            try bytes.write(to: next)
            opening.requestOpen([original, next])
            try await waitUntil { externalRoutes.values.count == 2 }
            #expect(externalRoutes.values.last?.fileURL == next)
            #expect(model.documentID == identity)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: original) == bytes)
        }
    }

    @Test("A rejected quit resumes queued requests after the canceled opening task finishes")
    func canceledQuitResumesFreshRequests() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let warmup = root.appendingPathComponent("Warmup.markdown")
            try Data("# Warmup".utf8).write(to: warmup)
            opening.requestOpen([warmup])
            try await waitUntil { externalRoutes.values.count == 1 }
            await Task.yield()
            let canceled = root.appendingPathComponent("Canceled.md")
            let resumed = root.appendingPathComponent("Resumed.md")
            try Data("# Canceled".utf8).write(to: canceled)
            try Data("# Resumed".utf8).write(to: resumed)
            opening.requestOpen([canceled])
            opening.prepareTermination()
            opening.cancelTermination()
            opening.requestOpen([resumed])
            try await waitUntil { externalRoutes.values.count == 2 }
            #expect(externalRoutes.values.map(\.fileURL) == [warmup, resumed])
            #expect(workspaceRoutes.values.isEmpty)
        }
    }

    @Test("Unresolved .md ownership opens an exact-source reader with every mutation route blocked")
    func unresolvedFileCanBeRead() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let warmup = root.appendingPathComponent("Warmup.markdown")
            try Data("# Warmup".utf8).write(to: warmup)
            opening.requestOpen([warmup])
            try await waitUntil { externalRoutes.values.count == 1 }
            let url = root.appendingPathComponent("Unknown.md")
            let bytes = Data("\u{FEFF}# Reading remains independent\r\n".utf8)
            try bytes.write(to: url)
            let registration = registryURL(root)
            try FileManager.default.createDirectory(at: registration.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic unreadable registration".utf8).write(to: registration)
            opening.requestOpen([url])
            try await waitUntil { externalRoutes.values.count == 2 }
            #expect(externalRoutes.values.last?.needsOwnershipResolution == true)
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            #expect(Data(model.snapshot?.source.utf8 ?? "".utf8) == bytes)
            #expect(model.error == nil)
            #expect(model.canRetryOwnership)
            #expect(model.canSelectMode(.read))
            #expect(!model.canSelectMode(.source))
            #expect(!model.canSelectMode(.livePreview))
            #expect(model.editorActions == nil)
            #expect(!model.canSave && !model.canImport && !model.canPresentImport)
            #expect(!(await model.save()))
            await #expect(throws: ExternalMarkdownWindowIssue.self) { try await model.captureImport() }
            await opening.retryExternalOwnership(model)
            try await waitUntil { !model.isBusy }
            #expect(!model.permitsSourceActions)
            #expect(model.canRetryOwnership)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Explicit ownership Retry enables a proven external session without changing its window or opening a workspace")
    func retryEnablesProvenExternalSession() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let url = root.appendingPathComponent("Unknown.md")
            let bytes = Data("# Retry the same exact source\r\n".utf8)
            try bytes.write(to: url)
            // Await application services, without creating a Triptych window.
            opening.requestOpen([url])
            try await waitUntil { externalRoutes.values.count == 1 }
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            let identity = model.documentID
            let editor = model.editorSession
            await opening.retryExternalOwnership(model)
            #expect(model.permitsSourceActions)
            #expect(!model.canRetryOwnership)
            #expect(model.canSelectMode(.source) && model.canSelectMode(.livePreview))
            #expect(model.canImport)
            #expect(model.documentID == identity)
            #expect(model.editorSession === editor)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("An unavailable application registry permits reading and explicit Retry after repair without opening Triptych")
    func unavailableBootstrapReaderRetriesIndependently() async throws {
        try await withRouting(initialRegistryFailure: true) { opening, _, root, externalRoutes, workspaceRoutes in
            let url = root.appendingPathComponent("Outside.md")
            let bytes = Data("# Independent during application recovery\r\n".utf8)
            try bytes.write(to: url)
            opening.requestOpen([url])
            try await waitUntil { externalRoutes.values.count == 1 }
            #expect(externalRoutes.values.first?.needsOwnershipResolution == true)
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            #expect(!model.permitsSourceActions)
            try FileManager.default.removeItem(at: registryURL(root))
            await opening.retryExternalOwnership(model)
            #expect(model.permitsSourceActions)
            #expect(model.canImport)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Retry of a registered Note retains a reading-only preview until explicit Open Note")
    func retryManagedNoteRequiresExplicitOpen() async throws {
        try await withRouting { opening, _, root, externalRoutes, workspaceRoutes in
            let warmup = root.appendingPathComponent("Warmup.markdown")
            try Data("# Warmup".utf8).write(to: warmup)
            opening.requestOpen([warmup])
            try await waitUntil { externalRoutes.values.count == 1 }
            let parent = root.appendingPathComponent("SyntheticTriptych", isDirectory: true)
            let folders = ["Analyses", "Topics", "Works"].map { parent.appendingPathComponent($0, isDirectory: true) }
            for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            let assignmentID: UUID
            do {
                let capabilities = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: folders[0], topicKnowledgeURL: folders[1], outputURL: folders[2],
                    portableContainerURL: parent, triptychName: "Synthetic Triptych"
                )
                assignmentID = capabilities.id
                await store.shutdownApplicationRuntime()
            } catch {
                await store.shutdownApplicationRuntime()
                throw error
            }
            let url = folders[1].appendingPathComponent("Managed.md")
            let bytes = Data("# Managed note preview\r\n".utf8)
            try bytes.write(to: url)
            let registration = registryURL(root)
            let intactRegistry = try Data(contentsOf: registration)
            try Data("synthetic registry failure".utf8).write(to: registration)
            opening.requestOpen([url])
            try await waitUntil { externalRoutes.values.count == 2 }
            #expect(externalRoutes.values.last?.needsOwnershipResolution == true)
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            let identity = model.documentID
            try intactRegistry.write(to: registration, options: .atomic)
            await opening.retryExternalOwnership(model)
            #expect(model.managedNote?.triptychID == assignmentID)
            #expect(model.managedNote?.reference.relativePath == "Managed.md")
            #expect(model.canOpenManagedNote)
            #expect(!model.permitsSourceActions && !model.canImport && !model.canSave)
            #expect(!model.canSelectMode(.source) && !model.canSelectMode(.livePreview))
            #expect(workspaceRoutes.values.isEmpty)
            #expect(model.documentID == identity)
            try await opening.openManagedPreview(model)
            #expect(workspaceRoutes.values.count == 1)
            #expect(workspaceRoutes.values.first?.triptychID == assignmentID)
            #expect(workspaceRoutes.values.first?.initialDocument == model.managedNote?.reference)
            #expect(!model.permitsSourceActions)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Unavailable unresolved source retains exact-file failure without authorizing editing", arguments: [false, true])
    func unavailableUnresolvedSource(permissionDenied: Bool) async throws {
        try await withRouting { _, _, root, _, _ in
            let url = root.appendingPathComponent("Unavailable.md")
            let model: ExternalMarkdownWindowModel
            if permissionDenied {
                model = ExternalMarkdownWindowModel(
                    url: url, needsOwnershipResolution: true,
                    openFile: { _ in
                        throw ExternalMarkdownFileError.permissionDenied
                    })
            } else {
                model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            }
            defer { model.close() }
            await model.open()
            #expect(model.snapshot == nil)
            #expect(model.error != nil)
            #expect(!model.permitsSourceActions && !model.canRetryOwnership && !model.canImport)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    enum InterruptedRetry: CaseIterable, Sendable { case canceled, closed, sourceChanged }

    @Test("Canceled, closed and changed-source Retry results cannot grant editing", arguments: InterruptedRetry.allCases)
    func interruptedRetryCannotAuthorize(reason: InterruptedRetry) async throws {
        try await withRouting { _, _, root, _, workspaceRoutes in
            let url = root.appendingPathComponent("Interrupted.md")
            let original = Data("# Original\r\n".utf8)
            try original.write(to: url)
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            let gate = RetryGate()
            let retry = Task { @MainActor in
                await model.retryOwnership {
                    await gate.pause()
                    return .external
                }
            }
            try await waitUntil { gate.isPaused }
            var expected = original
            switch reason {
            case .canceled: retry.cancel()
            case .closed: model.close()
            case .sourceChanged:
                expected = Data("# Peer revision\r\n".utf8)
                try expected.write(to: url)
            }
            gate.release()
            await retry.value
            #expect(!model.permitsSourceActions && !model.canSave && !model.canImport)
            #expect(workspaceRoutes.values.isEmpty)
            #expect(try Data(contentsOf: url) == expected)
        }
    }

    @MainActor
    private final class RetryGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isPaused: Bool { continuation != nil }
        func pause() async { await withCheckedContinuation { continuation = $0 } }
        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func registryURL(_ root: URL) -> URL {
        root.appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
    }

    private final class Routes<Value> {
        var values: [Value] = []
    }

    private func withRouting(
        initialRegistryFailure: Bool = false,
        _ body: (
            MarkdownFileOpeningController, ScholiumWindowLifecycleRegistry, URL,
            Routes<ExternalMarkdownWindowRoute>, Routes<TriptychWindowRoute>
        ) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/MarkdownFileOpeningLaunchTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if initialRegistryFailure {
            let registration = registryURL(root)
            try FileManager.default.createDirectory(at: registration.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic initial registry failure".utf8).write(to: registration)
        }
        let bootstrap = ApplicationBootstrapController {
            root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        }
        let opening = MarkdownFileOpeningController()
        defer { opening.prepareTermination() }
        let registry = ScholiumWindowLifecycleRegistry()
        let external = Routes<ExternalMarkdownWindowRoute>()
        let workspace = Routes<TriptychWindowRoute>()
        opening.connect(
            bootstrap: bootstrap,
            openExternalWindow: { external.values.append($0) },
            openWorkspaceWindow: { workspace.values.append($0) },
            lifecycleRegistry: registry
        )
        do {
            try await body(opening, registry, root, external, workspace)
        } catch {
            if case .ready(let store) = bootstrap.state { await store.shutdownApplicationRuntime() }
            throw error
        }
        if case .ready(let store) = bootstrap.state { await store.shutdownApplicationRuntime() }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    private func file(_ name: String) -> URL {
        // Routing is deliberately unbound: these URL events exercise launch
        // admission without opening a window, file session or real vault.
        URL(fileURLWithPath: "/nonexistent-scholium-launch-fixture/\(name)")
    }
}
