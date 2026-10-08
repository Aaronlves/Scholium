import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@MainActor
@Suite("External Markdown window lifecycle", .serialized)
struct ExternalMarkdownWindowLifecycleTests {
    @Test("The first external Review to Edit transition constructs a ready editor in the real offscreen window hierarchy")
    func firstReviewToEditConstructsEditor() async throws {
        try await withFile { url, _ in
            let prefix = "\u{FEFF}---\r\nunknown: 'keep' # fixture\r\n---\r\n"
            let body = "First 😀 e\u{301} paragraph.\n\nTail without newline"
            let source = prefix + body
            try Data(source.utf8).write(to: url)
            let host = OffscreenExternalWindow(url: url)
            do {
                try await host.waitUntil("production model attachment and file opening") {
                    guard let model = host.model else { return false }
                    return model.snapshot != nil && !model.isBusy
                }
                let model = try #require(host.model)
                #expect(model.mode == .read && !model.retainsEditor)
                #expect(!model.editorSession.hasAttachedWebView)
                try await host.waitForReadText("First 😀 e\u{301} paragraph.")

                // The production view, not this test, must allocate, attach and
                // initialize the editor when its owning model first requests Edit.
                model.selectMode(.livePreview)
                try await host.waitForEditor()
                let editor = model.editorSession
                let webView = try #require(editor.webView)
                let expectedCaret = try #require(
                    EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: prefix.utf16.count))
                try await host.waitUntil("initial exact body caret") {
                    editor.context?.selections == [.init(anchor: expectedCaret, head: expectedCaret)]
                }
                #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))
                #expect(!model.isDirty && model.error == nil && editor.errorMessage == nil)
                #expect(try Data(contentsOf: url) == Data(source.utf8))

                model.selectMode(.source)
                try await host.waitForEditor()
                #expect(model.mode == .source && editor.presentedMode == .source)
                #expect(model.editorSession === editor && editor.webView === webView)
                #expect(editor.context?.selections == [.init(anchor: expectedCaret, head: expectedCaret)])
                #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))

                model.selectMode(.read)
                try await host.waitUntil("return to Review") { model.mode == .read && !model.isBusy }
                try await host.waitForReadText("First 😀 e\u{301} paragraph.")
                #expect(model.editorSession === editor && editor.webView === webView)
                #expect(webView.isHidden && webView.isHiddenOrHasHiddenAncestor)

                model.selectMode(.livePreview)
                try await host.waitForEditor()
                #expect(model.editorSession === editor && editor.webView === webView)
                #expect(editor.context?.selections == [.init(anchor: expectedCaret, head: expectedCaret)])
                #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))
                #expect(!model.isDirty && model.error == nil && editor.errorMessage == nil)
                #expect(try Data(contentsOf: url) == Data(source.utf8))
                await host.closeAndDrain()
            } catch {
                await host.closeAndDrain()
                throw error
            }
        }
    }

    @Test(
        "Repeated opening coalesces and close or quit releases a session that finishes opening late",
        arguments: [false, true])
    func closeWhileOpening(termination: Bool) async throws {
        try await withFile { url, _ in
            let gate = PausedOpening()
            let model = ExternalMarkdownWindowModel(url: url, openFile: { try await gate.open($0) })
            defer { model.close() }
            let opening = Task { await model.open() }
            do {
                try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
                    await gate.waitForArrival()
                }
                await model.open()
                #expect(await gate.callCount == 1)
                #expect(model.canRequestClose)
                if termination { #expect(await model.prepareTermination()) } else { model.close() }
                await gate.release()
                await opening.value

                #expect(model.snapshot == nil)
                #expect(!model.canImport)
                let lateSession = try #require(await gate.openedSession)
                await #expect(throws: ExternalMarkdownFileError.closed) { try await lateSession.load() }
                await model.open()
                #expect(await gate.callCount == 1)
            } catch {
                await gate.release()
                await opening.value
                throw error
            }
        }
    }

    @Test(
        "A stalled external reader bounds quit, saves its healthy peer, and cannot save after the rejected attempt",
        arguments: [ScholiumLifecyclePhase.contentFlush, .applicationTermination])
    func stalledTerminationRetainsBufferAndFlushesPeer(phase: ScholiumLifecyclePhase) async throws {
        try await verifyStalledTermination(phase: phase, pausesSaveCapture: false)
    }

    @Test("A save capture completing after a rejected quit cannot start a late source write")
    func lateSaveCaptureCannotWriteAfterRejectedQuit() async throws {
        try await verifyStalledTermination(phase: .contentFlush, pausesSaveCapture: true)
    }

    private func verifyStalledTermination(phase: ScholiumLifecyclePhase, pausesSaveCapture: Bool) async throws {
        try await withEditor { stalled in
            try await withEditor { healthy in
                try await waitUntilIdle(stalled.model)
                try await waitUntilIdle(healthy.model)
                try stalled.insertNative("\r\nRetained after rejected quit")
                try healthy.insertNative("\r\nSaved by a healthy peer")
                let original = Data(try #require(stalled.model.snapshot).source.utf8)
                let retained = Data(stalled.editor.checkedSource.utf8)
                let savedPeer = Data(healthy.editor.checkedSource.utf8)
                let pause = PausedBridgeRequest()
                stalled.bridge.textQueriesBeforePause = pausesSaveCapture ? 1 : 0
                stalled.bridge.nextTextQueryPause = pause
                defer { pause.release() }
                var policy = ScholiumLifecyclePolicy()
                policy.contentFlush = phase == .contentFlush ? .milliseconds(200) : .seconds(3)
                policy.applicationTermination = phase == .applicationTermination ? .milliseconds(500) : .seconds(3)
                let registry = ExternalMarkdownWindowRegistry(policy: policy)
                registry.register(stalled.model)
                registry.register(healthy.model)
                defer {
                    registry.unregister(stalled.model)
                    registry.unregister(healthy.model)
                }
                let clock = ContinuousClock()
                let started = clock.now
                let flushing = Task { @MainActor in
                    await #expect(throws: ScholiumWindowLifecycleError.timedOut(phase)) {
                        try await registry.flushAll()
                    }
                }
                do {
                    try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: .seconds(3)) {
                        await pause.waitForArrival()
                    }
                } catch {
                    pause.release()
                    _ = await flushing.value
                    throw error
                }
                _ = await flushing.value

                #expect(started.duration(to: clock.now) < .seconds(1))
                #expect(registry.hasOpenWindows)
                #expect(stalled.model.error != nil)
                #expect(stalled.model.isDirty)
                #expect(stalled.model.isPreparingTermination)
                #expect(!stalled.model.canRequestClose)
                #expect(Data(stalled.editor.checkedSource.utf8) == retained)
                #expect(try Data(contentsOf: stalled.url) == original)
                #expect(try Data(contentsOf: healthy.url) == savedPeer)
                #expect(!healthy.model.isTerminating)

                // The old capture deliberately ignores cancellation. Its late
                // completion must thaw input without starting the rejected save.
                pause.release()
                try await waitUntilIdle(stalled.model)
                #expect(!stalled.model.isPreparingTermination)
                #expect(stalled.bridge.suspensionID == nil)
                #expect(stalled.editor.detachmentSuspensionID == nil)
                #expect(stalled.model.isDirty)
                #expect(Data(stalled.editor.checkedSource.utf8) == retained)
                #expect(try Data(contentsOf: stalled.url) == original)

                // An independent retry after the resource recovers can save.
                try await waitUntilIdle(healthy.model)
                try await registry.flushAll()
                #expect(try Data(contentsOf: stalled.url) == retained)
                await stalled.model.resumeInput()
                await healthy.model.resumeInput()
            }
        }
    }

    @Test("A conflicting external reader refuses quit while a healthy peer saves and both remain open")
    func failedTerminationStillFlushesPeer() async throws {
        try await withEditor { failing in
            try await withEditor { healthy in
                try await waitUntilIdle(failing.model)
                try await waitUntilIdle(healthy.model)
                try failing.insertNative("\r\nRetain the conflicting editor")
                try healthy.insertNative("\r\nSave this independent editor")
                let buffer = Data(failing.editor.checkedSource.utf8)
                let peer = Data(healthy.editor.checkedSource.utf8)
                let external = Data("# Concurrent replacement\r\n".utf8)
                try external.write(to: failing.url, options: .atomic)
                await failing.model.refreshFromDisk()
                try await waitUntilIdle(failing.model)
                #expect(failing.model.hasConflict)
                let conflict = failing.model.error
                let registry = ExternalMarkdownWindowRegistry()
                registry.register(failing.model)
                registry.register(healthy.model)
                defer {
                    registry.unregister(failing.model)
                    registry.unregister(healthy.model)
                }

                await #expect(throws: ExternalMarkdownWindowIssue.self) { try await registry.flushAll() }

                #expect(registry.hasOpenWindows)
                #expect(failing.model.hasConflict)
                #expect(failing.model.error == conflict)
                #expect(Data(failing.editor.checkedSource.utf8) == buffer)
                #expect(try Data(contentsOf: failing.url) == external)
                #expect(try Data(contentsOf: healthy.url) == peer)
                #expect(!failing.model.isTerminating)
                #expect(!healthy.model.isTerminating)
                #expect(failing.bridge.suspensionID == nil)
                #expect(healthy.bridge.suspensionID == nil)
            }
        }
    }

    @Test("Reopening the same URL keeps its dirty session and closing removes that route")
    func sameURLKeepsDirtySession() async throws {
        try await withEditor { fixture in
            let model = fixture.model
            let registry = ExternalMarkdownWindowRegistry.shared
            registry.register(model)
            defer { registry.unregister(model) }
            let identity = model.documentID
            try fixture.insertNative("\r\nUnsaved researcher's text")
            let captured = fixture.editor.checkedSource

            #expect(
                registry.reveal(
                    fixture.url.deletingLastPathComponent().appendingPathComponent("sub/../Outside.markdown"))
            )
            #expect(model.documentID == identity)
            #expect(model.editorSession === fixture.editor)
            #expect(model.editorSession.checkedSource == captured)
            #expect(model.isDirty)

            model.close()
            #expect(!registry.reveal(fixture.url))
        }
    }

    @Test(
        "File identity handles case spelling without merging distinct files or duplicating a retained session"
    )
    func caseSpellingKeepsOneAuthority() async throws {
        try await withEditor { fixture in
            let registry = ExternalMarkdownWindowRegistry()
            registry.register(fixture.model)
            defer { registry.unregister(fixture.model) }
            try fixture.insertNative("\r\nRetained across Finder spelling changes")
            let originalURL = fixture.model.originalURL
            let documentID = fixture.model.documentID
            let buffer = Data(fixture.editor.checkedSource.utf8)
            let starting = try #require(fixture.model.snapshot)
            let alternative = fixture.url.deletingLastPathComponent().appendingPathComponent(
                "outside.markdown")
            let values = try fixture.url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            let caseSensitive = try #require(values.volumeSupportsCaseSensitiveNames as Bool?)
            let duplicate = ExternalMarkdownWindowModel(url: alternative)
            defer {
                duplicate.close()
                registry.unregister(duplicate)
            }

            if caseSensitive {
                try Data(starting.source.utf8).write(to: alternative)
                #expect(!ExternalMarkdownWindowRegistry.referToSameFile(fixture.url, alternative))
                #expect(!registry.reveal(alternative))
                registry.register(duplicate)
                await duplicate.open()
                #expect(duplicate.snapshot != nil)
            } else {
                try FileManager.default.moveItem(at: fixture.url, to: alternative)
                #expect(ExternalMarkdownWindowRegistry.referToSameFile(fixture.url, alternative))
                #expect(registry.reveal(alternative))
                #expect(fixture.model.title == alternative.lastPathComponent)
                registry.register(duplicate)
                await duplicate.open()
                #expect(duplicate.snapshot == nil)
                #expect(!duplicate.canRequestClose)
            }
            #expect(fixture.model.originalURL == originalURL)
            #expect(fixture.model.documentID == documentID)
            #expect(fixture.model.editorSession === fixture.editor)
            #expect(Data(fixture.editor.checkedSource.utf8) == buffer)
            #expect(fixture.model.isDirty)
        }
    }

    @Test("Equally named copies and symlinks never confer the original's routing identity")
    func routingRejectsDifferentFilesAndLinks() async throws {
        try await withFile { url, original in
            let otherDirectory = url.deletingLastPathComponent().appendingPathComponent(
                "Other", isDirectory: true)
            try FileManager.default.createDirectory(
                at: otherDirectory, withIntermediateDirectories: false)
            let other = otherDirectory.appendingPathComponent(url.lastPathComponent)
            try Data(original.utf8).write(to: other)
            let link = url.deletingLastPathComponent().appendingPathComponent("Linked.markdown")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            #expect(!ExternalMarkdownWindowRegistry.referToSameFile(url, other))
            #expect(!ExternalMarkdownWindowRegistry.referToSameFile(url, link))
            #expect(
                ExternalMarkdownWindowRegistry.referToSameFile(
                    url, url.deletingLastPathComponent().appendingPathComponent("sub/../Outside.markdown")))
            #expect(try Data(contentsOf: url) == Data(original.utf8))
            #expect(try Data(contentsOf: other) == Data(original.utf8))
        }
    }

    @Test("Native document representation and presentation settings preserve exact source")
    func nativePresentationDoesNotEditSource() async throws {
        try await withFile { url, original in
            let model = ExternalMarkdownWindowModel(url: url)
            let window = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            defer {
                model.close()
                window.close()
            }
            model.attach(to: window)
            await model.open()
            let opened = try #require(model.snapshot)
            #expect(window.representedURL == url.standardizedFileURL)
            model.setDocumentTextScale(1.54)
            #expect(model.documentTextScale == 1.5)
            model.adjustDocumentTextScale(by: 10)
            #expect(model.documentTextScale == ScholiumMetrics.Document.maximumTextScale)
            model.setDocumentTextScale(-10)
            #expect(model.documentTextScale == ScholiumMetrics.Document.minimumTextScale)
            model.resetDocumentTextScale()
            model.colorScheme = .dark
            #expect(model.documentTextScale == ScholiumMetrics.Document.defaultTextScale)
            #expect(model.colorScheme == .dark)
            #expect(model.snapshot?.fingerprint == opened.fingerprint)
            #expect(Data(try #require(model.snapshot).source.utf8) == Data(original.utf8))
            #expect(!model.isDirty)
            #expect(try Data(contentsOf: url) == Data(original.utf8))
        }
    }

    @Test("Review selection Find admits only the current document and saved-source fingerprint")
    func readSelectionRejectsLatePageCallbacks() async throws {
        try await withFile { url, _ in
            let model = ExternalMarkdownWindowModel(url: url)
            defer { model.close() }
            await model.open()
            let starting = try #require(model.snapshot)
            let startingDocumentID = model.documentID
            model.acceptReadSelection(
                MarkdownReviewSelection(startLine: 1, endLine: 1, excerpt: "External"),
                documentID: startingDocumentID, fingerprint: starting.fingerprint)
            model.performFind(.useSelection)
            #expect(model.documentFind.query == "External")
            #expect(!model.retainsEditor)
            let updated = Data("# New saved text\r\n".utf8)
            try updated.write(to: url, options: .atomic)
            await model.refreshFromDisk()
            let current = try #require(model.snapshot)
            model.documentFind.setQuery("")
            model.performFind(.useSelection)
            #expect(model.documentFind.query.isEmpty)
            model.acceptReadSelection(
                MarkdownReviewSelection(startLine: 1, endLine: 1, excerpt: "New saved text"),
                documentID: model.documentID, fingerprint: current.fingerprint)
            model.acceptReadSelection(
                nil, documentID: startingDocumentID, fingerprint: starting.fingerprint)
            model.acceptReadSelection(
                MarkdownReviewSelection(startLine: 1, endLine: 1, excerpt: "Stale"),
                documentID: model.documentID, fingerprint: starting.fingerprint)
            model.performFind(.useSelection)
            #expect(model.documentFind.query == "New saved text")
            #expect(try Data(contentsOf: url) == updated)
        }
    }

    @Test(
        "Mode availability and execution both refuse composition, conflict, and an active operation")
    func modeGuardsMatchExecution() async throws {
        try await withEditor { fixture in
            let model = fixture.model
            #expect(model.canSelectMode(.read))
            #expect(model.canSelectMode(.livePreview))
            let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
            fixture.editor.updateInteraction(
                selections: [selection], line: 1, column: 1, lineCount: 1,
                documentVersion: fixture.editor.generation,
                interactionRevision: 0,
                context: MarkdownEditorContext(
                    selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                    tablePosition: nil,
                    composing: true, availableCommands: [], undoLabel: nil, redoLabel: nil))
            #expect(fixture.editor.isComposing)
            #expect(!model.canRequestClose)
            for mode in NotePresentationMode.allCases { #expect(!model.canSelectMode(mode)) }
            model.selectMode(.livePreview)
            #expect(model.mode == .source)
            fixture.editor.updateInteraction(
                selections: [selection], line: 1, column: 1, lineCount: 1,
                documentVersion: fixture.editor.generation,
                interactionRevision: 0,
                context: MarkdownEditorContext(
                    selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                    tablePosition: nil,
                    composing: false, availableCommands: [], undoLabel: nil, redoLabel: nil))
            model.importCommitInProgress = true
            for mode in NotePresentationMode.allCases { #expect(!model.canSelectMode(mode)) }
            model.selectMode(.livePreview)
            #expect(model.mode == .source)
            model.importCommitInProgress = false
            try fixture.insertNative("\r\nRetain this conflicting buffer")
            let external = Data("# External revision\r\n".utf8)
            try external.write(to: fixture.url, options: .atomic)
            await model.refreshFromDisk()
            #expect(model.hasConflict)
            #expect(!model.canSelectMode(.read))
            #expect(model.canSelectMode(.source))
            model.selectMode(.read)
            await model.waitForModeTransition()
            #expect(model.mode == .source)
            #expect(try Data(contentsOf: fixture.url) == external)
            model.close()
            for mode in NotePresentationMode.allCases { #expect(!model.canSelectMode(mode)) }
        }
    }

    @Test("A clean window reloads exact saved bytes after atomic replacement")
    func cleanReplacementReloads() async throws {
        try await withFile { url, original in
            let model = ExternalMarkdownWindowModel(url: url)
            defer { model.close() }
            await model.open()
            let starting = try #require(model.snapshot)
            #expect(Data(starting.source.utf8) == Data(original.utf8))
            let replacement = "\u{FEFF}# Current saved source\r\nunknown: 'preserve'"
            try Data(replacement.utf8).write(to: url, options: .atomic)

            await model.refreshFromDisk()

            let refreshed = try #require(model.snapshot)
            #expect(Data(refreshed.source.utf8) == Data(replacement.utf8))
            #expect(refreshed.fingerprint == DocumentFingerprint(content: replacement))
            #expect(!model.isDirty)
            #expect(!model.hasConflict)
            #expect(model.mode == .read)
        }
    }

    @Test("A dirty external change preserves the buffer and explicit reload clears its conflict")
    func dirtyChangeAndExplicitReload() async throws {
        try await withEditor { fixture in
            let model = fixture.model
            try fixture.insertNative("\r\nUnsaved local edit")
            let buffer = fixture.editor.checkedSource
            let starting = try #require(model.snapshot)
            let external = "# Other editor's revision\r\n"
            try Data(external.utf8).write(to: fixture.url, options: .atomic)

            await model.refreshFromDisk()

            #expect(model.hasConflict)
            #expect(model.isDirty)
            #expect(model.snapshot?.fingerprint == starting.fingerprint)
            #expect(Data(model.editorSession.checkedSource.utf8) == Data(buffer.utf8))
            #expect(try Data(contentsOf: fixture.url) == Data(external.utf8))
            #expect(!model.canImport)
            #expect(!model.canSave)

            await model.reloadFromDisk()

            #expect(model.snapshot?.fingerprint == DocumentFingerprint(content: external))
            #expect(!model.hasConflict)
            #expect(!model.isDirty)
            #expect(model.editorSession !== fixture.editor)
            #expect(model.mode == .source)
            #expect(try Data(contentsOf: fixture.url) == Data(external.utf8))
        }
    }

    @Test(
        "Temporary file unavailability retains the dirty buffer and permits a verified save after restoration"
    )
    func unavailableOriginalCanRecoverWithoutDiscard() async throws {
        try await withEditor { fixture in
            let model = fixture.model
            try fixture.insertNative("\r\nRetained while the original is unavailable")
            let buffer = Data(fixture.editor.checkedSource.utf8)
            let parked = fixture.url.deletingLastPathComponent().appendingPathComponent("Parked.markdown")
            try FileManager.default.moveItem(at: fixture.url, to: parked)
            await model.refreshFromDisk()
            #expect(model.error != nil)
            #expect(model.isDirty)
            #expect(!model.hasConflict)
            #expect(Data(model.editorSession.checkedSource.utf8) == buffer)
            try FileManager.default.moveItem(at: parked, to: fixture.url)
            await model.refreshFromDisk()
            #expect(model.error == nil)
            #expect(!model.hasConflict)
            #expect(await model.save())
            #expect(try Data(contentsOf: fixture.url) == buffer)
        }
    }

    @Test(
        "Reselecting the original repairs access without replacing retained editor input or adopting another revision"
    )
    func reauthorizationPreservesEditor() async throws {
        try await withEditor { fixture in
            try fixture.insertNative("\r\nRetained during file selection")
            let documentID = fixture.model.documentID
            let buffer = Data(fixture.editor.checkedSource.utf8)
            await fixture.model.open(using: fixture.url)
            #expect(fixture.model.documentID == documentID)
            #expect(fixture.model.editorSession === fixture.editor)
            #expect(fixture.model.isDirty)
            #expect(await fixture.model.save())
            #expect(try Data(contentsOf: fixture.url) == buffer)
            let external = Data("# Different revision\r\n".utf8)
            try external.write(to: fixture.url, options: .atomic)
            await fixture.model.open(using: fixture.url)
            #expect(fixture.model.hasConflict)
            #expect(fixture.model.editorSession === fixture.editor)
            #expect(Data(fixture.editor.checkedSource.utf8) == buffer)
            #expect(try Data(contentsOf: fixture.url) == external)
        }
    }

    @Test(
        "An uncertain import retains its recovery route and prevents another copy while original editing remains available"
    )
    func pendingImportRecoveryPreventsDuplicate() async throws {
        try await withEditor { fixture in
            let reference = VaultNoteReference(
                vaultID: UUID(), vaultName: "Topics", vaultRole: .topicKnowledge,
                relativePath: "Outside 2.md")
            fixture.model.pendingImport = ExternalMarkdownImportResult(
                reference: reference, triptychID: UUID(), message: "Synthetic recovery",
                requiresRecovery: true)
            #expect(!fixture.model.canImport)
            #expect(fixture.model.canPresentImport)
            await #expect(throws: (any Error).self) { try await fixture.model.captureImport() }
            try fixture.insertNative("\r\nOriginal editing remains available")
            #expect(fixture.model.canSave)
            #expect(await fixture.model.save())
            #expect(fixture.model.pendingImport?.reference == reference)
            #expect(!fixture.model.canImport)
        }
    }

    enum PendingInputRoute: CaseIterable, Sendable {
        case importCopy, termination, externalRefresh, review
    }

    enum ResumeFailureRoute: CaseIterable, Sendable {
        case externalRefresh, review, cancelledTermination
    }

    @Test(
        "A failed input resume retains its matching token and exact buffer until a successful retry",
        arguments: ResumeFailureRoute.allCases)
    func failedResumeCanRetry(route: ResumeFailureRoute) async throws {
        try await withEditor { fixture in
            let model = fixture.model
            try fixture.insertNative("\r\nRetained after a failed resume 🦉")
            let buffer = Data(fixture.editor.checkedSource.utf8)
            let starting = try #require(model.snapshot)
            fixture.bridge.resumeFailuresRemaining = 1

            switch route {
            case .externalRefresh:
                await model.refreshFromDisk()
                #expect(try Data(contentsOf: fixture.url) == Data(starting.source.utf8))
            case .review:
                model.selectMode(.read)
                await model.waitForModeTransition()
                #expect(model.mode == .read)
                #expect(try Data(contentsOf: fixture.url) == buffer)
            case .cancelledTermination:
                #expect(await model.prepareTermination())
                await model.resumeInput()
                #expect(!model.isTerminating)
                #expect(try Data(contentsOf: fixture.url) == buffer)
            }

            let retainedToken = try #require(fixture.bridge.suspensionID)
            #expect(fixture.editor.detachmentSuspensionID == retainedToken)
            #expect(model.inputResumeError != nil)
            #expect(model.canResumeInput)
            #expect(!model.canSave)
            #expect(!model.canImport)
            #expect(model.editorActions == nil)
            for mode in NotePresentationMode.allCases { #expect(!model.canSelectMode(mode)) }
            #expect(Data(fixture.editor.checkedSource.utf8) == buffer)

            await model.resumeInput()

            #expect(fixture.bridge.suspensionID == nil)
            #expect(fixture.editor.detachmentSuspensionID == nil)
            #expect(model.inputResumeError == nil)
            #expect(!model.canResumeInput)
            #expect(model.canSelectMode(.source))
            #expect(Data(fixture.editor.checkedSource.utf8) == buffer)
        }
    }

    @Test(
        "Lifecycle boundaries reconcile browser input before its native delta arrives",
        arguments: PendingInputRoute.allCases)
    func pendingBrowserInput(route: PendingInputRoute) async throws {
        try await withEditor { fixture in
            let model = fixture.model
            let original = try #require(model.snapshot)
            fixture.bridge.insertBrowserOnly("\r\nPending cafe\u{301} 🦉")
            let candidate = Data(fixture.bridge.source.utf8)
            #expect(!model.isDirty)

            switch route {
            case .review:
                model.selectMode(.read)
                await model.waitForModeTransition()
                #expect(model.mode == .read)
                #expect(try Data(contentsOf: fixture.url) == candidate)
                #expect(!model.isDirty)
                #expect(fixture.bridge.suspensionID == nil)
            case .importCopy:
                let captured = try await model.captureImport()
                #expect(captured == candidate)
                #expect(model.isDirty)
                #expect(model.snapshot?.fingerprint == original.fingerprint)
                #expect(try Data(contentsOf: fixture.url) == Data(original.source.utf8))
            case .termination:
                #expect(await model.prepareTermination())
                #expect(try Data(contentsOf: fixture.url) == candidate)
                #expect(!model.isDirty)
                let heldSuspension = try #require(fixture.bridge.suspensionID)
                await model.refreshFromDisk()
                #expect(fixture.bridge.suspensionID == heldSuspension)
                #expect(!model.canImport)
                await model.resumeInput()
                #expect(fixture.bridge.suspensionID == nil)
            case .externalRefresh:
                let external = Data("# Saved by another editor\r\n".utf8)
                try external.write(to: fixture.url, options: .atomic)
                await model.refreshFromDisk()
                #expect(model.hasConflict)
                #expect(model.isDirty)
                #expect(model.editorSession === fixture.editor)
                #expect(Data(model.editorSession.checkedSource.utf8) == candidate)
                #expect(model.snapshot?.fingerprint == original.fingerprint)
                #expect(try Data(contentsOf: fixture.url) == external)
                #expect(fixture.bridge.suspensionID == nil)
            }
        }
    }

    private func withFile(_ operation: @MainActor (URL, String) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(
                ".build/ExternalMarkdownWindowLifecycleTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Outside.markdown")
        let original = "\u{FEFF}# External\r\n"
        try Data(original.utf8).write(to: url)
        try await operation(url, original)
    }

    private func withEditor(_ operation: @MainActor (EditorFixture) async throws -> Void) async throws {
        try await withFile { url, _ in
            let bridge = BufferBridge()
            let editor = MarkdownEditorSession(bridgeDispatcher: bridge)
            let model = ExternalMarkdownWindowModel(url: url, editorSession: editor)
            defer { model.close() }
            await model.open()
            let opened = try #require(model.snapshot)
            model.selectMode(.source)
            let webView = WKWebView()
            editor.attach(webView)
            defer { if editor.hasAttachedWebView { editor.detach(webView) } }
            editor.loadDocument(opened.source, documentID: model.documentID, mode: .source)
            editor.editorBecameReady()
            try #require(try await editor.waitUntilLoadedForSave())
            try await operation(EditorFixture(url: url, model: model, editor: editor, bridge: bridge))
        }
    }

    private func waitUntilIdle(_ model: ExternalMarkdownWindowModel) async throws {
        try await withScholiumLifecycleDeadline(phase: .contentFlush, timeout: .seconds(3)) {
            while model.isBusy { await Task.yield() }
        }
    }

    /// Uses the complete external window view. Its production attachment owns
    /// the model/window connection, and SwiftUI alone constructs both surfaces.
    /// The window is never ordered or activated.
    @MainActor
    private final class OffscreenExternalWindow {
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var retainedModel: ExternalMarkdownWindowModel?
        private var closed = false

        var model: ExternalMarkdownWindowModel? {
            window.delegate as? ExternalMarkdownWindowModel
        }

        init(url: URL) {
            _ = NSApplication.shared
            // The external view reads readiness but never starts bootstrap.
            // If that changes, its resolver still confines state to this fixture.
            let bootstrap = ApplicationBootstrapController {
                url.deletingLastPathComponent().appendingPathComponent("ApplicationSupport", isDirectory: true)
            }
            let content = ExternalMarkdownWindowView(url: url)
                .environmentObject(bootstrap)
                .environmentObject(ScholiumApplicationDelegate())
            let hosting = NSHostingController(rootView: content)
            hosting.sizingOptions = []
            hostingController = hosting
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 720, height: 520))
            hosting.view.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
            hosting.view.autoresizingMask = [.width, .height]
            hosting.view.layoutSubtreeIfNeeded()
            #expect(!window.isVisible)
        }

        func waitForEditor() async throws {
            try await waitUntil("\(model?.mode.rawValue ?? "unknown") editor readiness and native visibility") {
                guard let model = self.model, model.editorReady, let webView = model.editorSession.webView else { return false }
                return webView.window === self.window && !webView.isHiddenOrHasHiddenAncestor
                    && webView.bounds.width > 0 && webView.bounds.height > 0
            }
            let webView = try #require(model?.editorSession.webView)
            let hasContent =
                try await webView.callAsyncJavaScript(
                    "return document.querySelector('.cm-content')?.getBoundingClientRect().height > 0;",
                    arguments: [:], in: nil, contentWorld: .page) as? Bool
            #expect(hasContent == true)
        }

        func waitForReadText(_ text: String) async throws {
            try await waitUntil("rendered Review text") {
                guard let root = self.hostingController?.view else { return false }
                for webView in self.descendants(root).compactMap({ $0 as? WKWebView })
                where webView !== self.model?.editorSession.webView && !webView.isHiddenOrHasHiddenAncestor {
                    if try await webView.callAsyncJavaScript(
                        "return document.querySelector('#scholium-document')?.textContent.includes(expected) === true;",
                        arguments: ["expected": text], in: nil, contentWorld: .page) as? Bool == true
                    {
                        return true
                    }
                }
                return false
            }
        }

        func waitUntil(_ phase: String, _ condition: @escaping @MainActor () async throws -> Bool) async throws {
            do {
                try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(8)) {
                    while !(try await condition()) {
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(20))
                    }
                }
            } catch {
                let model = model
                let editor = model?.editorSession
                let webView = editor?.webView
                Issue.record(
                    Comment(
                        rawValue:
                            "External window failed at \(phase): mode=\(model?.mode.rawValue ?? "none") "
                            + "retains=\(model?.retainsEditor ?? false) ready=\(editor?.isReady ?? false) loaded=\(editor?.isLoaded ?? false) "
                            + "presented=\(String(describing: editor?.presentedMode)) hidden=\(webView?.isHiddenOrHasHiddenAncestor ?? false) "
                            + "frame=\(webView?.frame ?? .zero) windowAttached=\(webView?.window === window) visible=\(window.isVisible) "
                            + "modelError=\(model?.error ?? "none") editorError=\(editor?.errorMessage ?? "none")"))
                throw error
            }
            #expect(!window.isVisible)
        }

        func close() {
            guard !closed else { return }
            #expect(!window.isVisible)
            closed = true
            retainedModel = model
            retainedModel?.close()
            window.contentViewController = nil
            hostingController = nil
            window.close()
        }

        func closeAndDrain() async {
            close()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while retainedModel?.editorSession.hasAttachedWebView == true, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(retainedModel?.editorSession.hasAttachedWebView != true)
        }

        private func descendants(_ root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap(descendants)
        }
    }

    @MainActor
    private struct EditorFixture {
        let url: URL
        let model: ExternalMarkdownWindowModel
        let editor: MarkdownEditorSession
        let bridge: BufferBridge

        func insertNative(_ exact: String) throws {
            let end = EditorSourceOffsetMap(source: bridge.source).editorUTF16Length
            let next = editor.generation + 1
            try #require(
                editor.acceptEditorChanges(
                    [
                        .init(
                            from: end, to: end, insert: exact.replacingOccurrences(of: "\r\n", with: "\n"),
                            exactInsert: exact)
                    ],
                    baseGeneration: editor.generation, resultingGeneration: next
                ))
            bridge.source += exact
            bridge.generation = next
        }
    }

    /// Returns production-shaped bridge envelopes without loading JavaScript.
    /// Browser-only insertion models a committed edit whose delta is still queued.
    @MainActor
    private final class BufferBridge: MarkdownEditorBridgeDispatching {
        var source = ""
        var generation = 0
        var suspensionID: String?
        var resumeFailuresRemaining = 0
        var nextTextQueryPause: PausedBridgeRequest?
        var textQueriesBeforePause = 0

        func insertBrowserOnly(_ exact: String) {
            source += exact
            generation += 1
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            var text: String?
            var recovery: MarkdownEditorRecoverySnapshot?
            var superseded: Bool?
            switch request.operation {
            case .initialize(let source, _, _, _, _):
                self.source = source
                generation = 0
            case .queryText:
                if let pause = nextTextQueryPause {
                    if textQueriesBeforePause > 0 {
                        textQueriesBeforePause -= 1
                    } else {
                        nextTextQueryPause = nil
                        await pause.suspend()
                    }
                }
                text = source
            case .captureRecovery:
                recovery = recoverySnapshot(request)
            case .suspendForDetachment(let id):
                suspensionID = id
                recovery = recoverySnapshot(request)
            case .resumeAfterDetachment(let id):
                guard suspensionID == id else { throw MarkdownEditorSession.SessionError.staleRequest }
                if resumeFailuresRemaining > 0 {
                    resumeFailuresRemaining -= 1
                    throw MarkdownEditorSession.SessionError.bridgeRejected("Synthetic input resume failure.")
                }
                suspensionID = nil
            case .acknowledgeCommittedSnapshot(let expected, let committed, _, _, _):
                superseded = !source.utf8.elementsEqual(expected.utf8)
                if superseded == false { source = committed }
                text = source
            default:
                break
            }
            var result: [String: Any] = [
                "requestID": request.requestID.uuidString,
                "resultingGeneration": generation,
                "interactionRevision": generation,
                "sourceChanged": false,
                "selections": [["anchor": 0, "head": 0]],
                "accepted": true,
            ]
            if let text { result["text"] = text }
            if let superseded { result["commitSuperseded"] = superseded }
            if let recovery {
                result["recovery"] = [
                    "documentID": recovery.documentID, "fingerprint": recovery.fingerprint,
                    "generation": recovery.generation, "ranges": [["anchor": 0, "head": 0]],
                    "source": recovery.source, "undoHistoryPreserved": false,
                    "dirty": recovery.dirty, "focusTarget": "editor",
                ]
            }
            return result
        }

        private func recoverySnapshot(_ request: MarkdownEditorRequest)
            -> MarkdownEditorRecoverySnapshot
        {
            .init(
                documentID: request.documentID, fingerprint: request.startingFingerprint,
                generation: generation, ranges: [.init(anchor: 0, head: 0)], source: source,
                stateJSON: nil, undoHistoryPreserved: false, dirty: generation > 0, focusTarget: .editor)
        }
    }

    @MainActor
    private final class PausedBridgeRequest {
        private let arrivals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func suspend() async {
            arrivals.continuation.yield(())
            guard !released else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func waitForArrival() async {
            var iterator = arrivals.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    private actor PausedOpening {
        private let arrivals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var callCount = 0
        private(set) var openedSession: ExternalMarkdownFileSession?

        func open(_ url: URL) async throws -> (
            session: ExternalMarkdownFileSession, snapshot: ExternalMarkdownFileSnapshot
        ) {
            callCount += 1
            if callCount == 1 {
                arrivals.continuation.yield(())
                await withCheckedContinuation { continuation = $0 }
            }
            let opened = try ExternalMarkdownFileSession.open(url)
            openedSession = opened.session
            return opened
        }

        func waitForArrival() async {
            var iterator = arrivals.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }
}
