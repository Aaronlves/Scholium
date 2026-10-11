import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Markdown file launch routing", .serialized)
struct MarkdownFileOpeningLaunchTests {
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

    @Test("Startup connection drains queued external files once without requiring a workspace scene")
    func startupConnectionDrainsPendingFilesOnce() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/MarkdownFileOpeningLaunchTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("Before Connection.md")
        let second = root.appendingPathComponent("After Connection.markdown")
        let firstBytes = Data("\u{FEFF}# Queued before startup\r\n".utf8)
        let secondBytes = Data("# Later external file\n\nKeep this final line".utf8)
        try firstBytes.write(to: first)
        try secondBytes.write(to: second)
        var storageResolutions = 0
        let bootstrap = ApplicationBootstrapController {
            storageResolutions += 1
            return root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        }
        let opening = MarkdownFileOpeningController()
        let registry = ScholiumWindowLifecycleRegistry()
        let external = Routes<ExternalMarkdownWindowRoute>()
        let workspace = Routes<TriptychWindowRoute>()
        let openExternal: (ExternalMarkdownWindowRoute) -> Void = { external.values.append($0) }
        let openWorkspace: (TriptychWindowRoute) -> Void = { workspace.values.append($0) }
        do {
            opening.requestOpen([first])
            #expect(external.values.isEmpty)
            #expect(!bootstrap.isReady)
            opening.connect(
                bootstrap: bootstrap, openExternalWindow: openExternal,
                openWorkspaceWindow: openWorkspace, lifecycleRegistry: registry
            )
            // Startup and scene-phase callbacks can bind the same scene
            // action again while asynchronous bootstrap is still starting.
            opening.connect(
                bootstrap: bootstrap, openExternalWindow: openExternal,
                openWorkspaceWindow: openWorkspace, lifecycleRegistry: registry
            )
            #expect(storageResolutions == 0)
            #expect(external.values.isEmpty)
            try await waitUntil { !external.values.isEmpty }
            #expect(bootstrap.isReady)
            #expect(external.values == [ExternalMarkdownWindowRoute(fileURL: first)])

            opening.connect(
                bootstrap: bootstrap, openExternalWindow: openExternal,
                openWorkspaceWindow: openWorkspace, lifecycleRegistry: registry
            )
            // This later file is a serial-queue witness: it can route only
            // after the original pending request has finished.
            opening.requestOpen([second])
            try await waitUntil { external.values.count >= 2 }
            #expect(
                external.values == [
                    ExternalMarkdownWindowRoute(fileURL: first),
                    ExternalMarkdownWindowRoute(fileURL: second),
                ])
            #expect(storageResolutions == 1)
            #expect(workspace.values.isEmpty)
            #expect(!registry.hasRegisteredWindows)
            #expect(try Data(contentsOf: first) == firstBytes)
            #expect(try Data(contentsOf: second) == secondBytes)
        } catch {
            opening.prepareTermination()
            if case .ready(let store) = bootstrap.state { await store.shutdownApplicationRuntime() }
            throw error
        }
        opening.prepareTermination()
        if case .ready(let store) = bootstrap.state { await store.shutdownApplicationRuntime() }
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
            try await waitUntil { !model.isBusy }
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
            try await waitUntil { !model.isBusy }
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

    @Test("Delegate cold and warm file callbacks leave saved Triptych runtimes inactive")
    func delegateFileCallbacksRemainIndependent() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/DelegateMarkdownRouting-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registration = try seedRegistration(in: root)
        let first = root.appendingPathComponent("Cold.md")
        let second = root.appendingPathComponent("Warm.markdown")
        let bytes = Data("\u{FEFF}# Independent 中文 😀\r\n".utf8)
        try bytes.write(to: first)
        try bytes.write(to: second)
        let delegate = ScholiumApplicationDelegate()
        let opening = delegate.markdownFiles
        defer { opening.prepareTermination() }
        let bootstrap = ApplicationBootstrapController {
            root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        }
        let external = Routes<ExternalMarkdownWindowRoute>()
        let workspace = Routes<TriptychWindowRoute>()
        delegate.application(NSApplication.shared, open: [first])
        #expect(external.values.isEmpty && !bootstrap.isReady)
        opening.connect(
            bootstrap: bootstrap,
            openExternalWindow: { external.values.append($0) },
            openWorkspaceWindow: { workspace.values.append($0) },
            lifecycleRegistry: delegate.windowLifecycleRegistry)
        try await waitUntil { external.values.count == 1 }
        guard case .ready(let store) = bootstrap.state else {
            Issue.record("Missing synthetic store")
            return
        }
        do {
            delegate.application(NSApplication.shared, open: [second, second])
            try await waitUntil { external.values.count == 2 }
            #expect(external.values.map(\.fileURL) == [first, second])
            #expect(external.values.allSatisfy { !$0.needsOwnershipResolution })
            #expect(workspace.values.isEmpty)
            #expect(store.workspaceSnapshots.isEmpty && store.workspaceActivations.isEmpty)
            #expect(try await store.registeredTriptychs().map(\.id) == [registration.id])
            #expect(try Data(contentsOf: first) == bytes && Data(contentsOf: second) == bytes)
            delegate.windowLifecycleRegistry.beginTerminationAttempt()
            delegate.application(NSApplication.shared, open: [root.appendingPathComponent("Rejected.md")])
            #expect(external.values.count == 2)
            delegate.windowLifecycleRegistry.endTerminationAttempt()
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("A fresh registry change routes an earlier external path through its managed owner")
    func registryChangeCannotReuseExternalClassification() async throws {
        try await withRouting { opening, _, root, external, workspace in
            let parent = root.appendingPathComponent("Registered/Topics", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let original = parent.appendingPathComponent("Note.md")
            let bytes = Data("# Same exact source\r\n".utf8)
            try bytes.write(to: original)
            opening.requestOpen([original])
            try await waitUntil { external.values.count == 1 }
            let assignment = try seedRegistration(in: root)
            opening.requestOpen([original])
            try await waitUntil { workspace.values.count == 1 }
            #expect(external.values.count == 1)
            #expect(workspace.values.first?.triptychID == assignment.id)
            #expect(workspace.values.first?.initialDocument?.vaultID == assignment.topicKnowledgeVaultID)
            #expect(workspace.values.first?.initialDocument?.relativePath == "Note.md")
            #expect(try Data(contentsOf: original) == bytes)
        }
    }

    @Test("Full classification preserves non-Note exclusions and unavailable registered-root routing")
    func fullClassifierPreservesBoundaries() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/ClassifierBoundaries-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = try seedRegistration(in: root)
        let folder = root.appendingPathComponent("Registered/Topics")
        let vault = RegisteredVault(
            id: triptych.topicKnowledgeVaultID, name: "Topics", role: .topicKnowledge,
            canonicalPath: folder.path)
        let assignment = TriptychAssignment(triptych: triptych, vaults: [.topicKnowledge: vault], hasCommonParent: true)
        for relative in ["Attachments/Original.md", ".scholium/state.md", "Nested/.hidden/Original.md", "Outside.markdown", "../Outside.md"] {
            #expect(MarkdownFileOpeningController.managedNote(at: folder.appendingPathComponent(relative), assignments: [assignment]) == nil)
        }
        #expect(
            MarkdownFileOpeningController.managedNote(
                at: root.appendingPathComponent("Registered/Topics-neighbor/Note.md"), assignments: [assignment]) == nil)
        // An unavailable registered root must still route guarded opening by its
        // recorded path, rather than authorizing an independent source writer.
        try FileManager.default.removeItem(at: folder)
        let managed = MarkdownFileOpeningController.managedNote(at: folder.appendingPathComponent("Nested/Note.md"), assignments: [assignment])
        #expect(managed?.triptychID == triptych.id)
        #expect(managed?.reference.vaultID == vault.id && managed?.reference.relativePath == "Nested/Note.md")
    }

    private struct LaunchRegistry: Encodable {
        let schemaVersion = 3
        let vaults: [RegisteredVault]
        let triptychs: [ScholiumTriptych]
        let defaultTriptychID: UUID
    }

    private func seedRegistration(in root: URL) throws -> ScholiumTriptych {
        var vaults: [RegisteredVault] = []
        for slot in WorkspaceVaultSlot.allCases {
            let folder = root.appendingPathComponent("Registered/\(slot.displayName)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            vaults.append(RegisteredVault(name: slot.displayName, role: slot.vaultRole, canonicalPath: folder.path))
        }
        let triptych = ScholiumTriptych(
            name: "Synthetic registered Triptych",
            paperAnalysisVaultID: vaults[0].id, topicKnowledgeVaultID: vaults[1].id, outputVaultID: vaults[2].id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = registryURL(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(LaunchRegistry(vaults: vaults, triptychs: [triptych], defaultTriptychID: triptych.id)).write(to: url)
        return triptych
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
}
