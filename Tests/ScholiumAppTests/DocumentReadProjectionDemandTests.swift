import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Document read projection demand", .serialized)
struct DocumentReadProjectionDemandTests {
    @Test("Pending and active Edit or Source never invoke the Review renderer", arguments: [MarkdownEditorMode.livePreview, .source])
    func editorDoesNotRenderReview(mode: MarkdownEditorMode) async {
        let session = DocumentSessionModel(key: nil)
        let editorIdentity = ObjectIdentifier(session.editorSession)
        let fingerprint = DocumentFingerprint(content: "Committed source.")
        var calls = 0
        session.preparePresentationMode(mode.presentationMode)
        #expect(session.presentationMode == .read)
        #expect(session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: fingerprint) == nil)
        let pending = await session.loadReadProjectionIfNeeded {
            calls += 1
            return "unused"
        }
        #expect(pending == nil)

        session.beginEditing(in: mode)
        session.editingSource = "Unsaved source."
        session.originalEditingSource = "Committed source."
        let active = await session.loadReadProjectionIfNeeded {
            calls += 1
            return "unused"
        }
        #expect(active == nil)
        #expect(session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: fingerprint) == nil)
        #expect(calls == 0)
        #expect(session.renderedReadHTML.utf8.count == 0)
        #expect(session.editingSource == "Unsaved source.")
        #expect(session.originalEditingSource == "Committed source.")
        #expect(ObjectIdentifier(session.editorSession) == editorIdentity)
    }

    @Test("Review demand binds document and revision and retains a previously viewed projection")
    func reviewTaskIdentity() async {
        let session = DocumentSessionModel(key: nil)
        let fingerprint = DocumentFingerprint(content: "First.")
        let nextFingerprint = DocumentFingerprint(content: "Second.")
        session.preparePresentationMode(.livePreview)
        let initial = session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: fingerprint)
        session.beginEditing(in: .livePreview)
        session.finishEditing()
        let review = session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: fingerprint)
        #expect(review != nil && review != initial)
        #expect(review != session.readProjectionTaskIdentity(relativePath: "Other.md", fingerprint: fingerprint))
        #expect(review != session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: nextFingerprint))
        var calls = 0
        let html = await session.loadReadProjectionIfNeeded {
            calls += 1
            return "<p>First.</p>"
        }
        #expect(html == "<p>First.</p>")
        session.renderedReadHTML = html ?? ""
        session.renderedReadFingerprint = fingerprint.sha256
        session.renderedReadReadyFingerprint = fingerprint.sha256
        session.beginEditing(in: .source)
        #expect(session.readProjectionTaskIdentity(relativePath: "Note.md", fingerprint: fingerprint) == nil)
        #expect(
            await session.loadReadProjectionIfNeeded {
                calls += 1
                return "unused"
            } == nil)
        #expect(calls == 1)
        #expect(session.renderedReadHTML == "<p>First.</p>")
        #expect(session.renderedReadReadyFingerprint == fingerprint.sha256)
    }

    @Test("Failed initial editor preparation retains the existing committed read fallback")
    func initialEditorFailureNeedsReview() async {
        let session = DocumentSessionModel(key: nil)
        session.preparePresentationMode(.livePreview)
        #expect(!session.requiresReadProjection)
        session.editorSession.reportError("Synthetic startup failure")
        #expect(!session.isEditing && session.pendingEditorMode == .livePreview)
        #expect(session.requiresReadProjection)
        let gate = DocumentEditorPresentationGate()
        #expect(gate.mountsReadSurface(presentsEditor: true, allowsPendingRecovery: true))
        #expect(
            gate.allowsReadHitTesting(
                documentID: "fixture", presentsEditor: true, editorIsReady: false, allowsPendingRecovery: true))
        let document = NoteDocument(relativePath: "Fallback.md", rawContent: "A readable committed paragraph.\n")
        let cache = DocumentReadProjectionCache()
        let key = DocumentReadProjectionKey(
            workspaceID: nil, stableTarget: "fallback", relativePath: document.relativePath, fingerprint: document.fingerprint)
        let html = await session.loadReadProjectionIfNeeded {
            await cache.html(for: key, source: document.rawContent)
        }
        #expect(html?.contains("A readable committed paragraph.") == true)
        session.beginEditing(in: .livePreview)
        #expect(!session.requiresReadProjection, "An active editor error presents editorFailure, not Review HTML.")

        let creation = DocumentSessionModel(key: nil)
        creation.preparePresentationMode(.livePreview)
        creation.beginManagedCreationEntry(bodyStartUTF16: 0)
        creation.editorSession.reportError("Synthetic managed creation failure")
        #expect(!creation.requiresReadProjection)
    }

    @Test("A cancelled or no-longer-visible Review cannot publish its delayed HTML", arguments: [false, true])
    func delayedProjectionCannotOutliveDemand(cancel: Bool) async throws {
        let session = DocumentSessionModel(key: nil)
        let gate = RenderGate()
        let task = Task { await session.loadReadProjectionIfNeeded { await gate.render() } }
        defer {
            task.cancel()
            gate.resume()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !gate.started, ContinuousClock.now < deadline { await Task.yield() }
        try #require(gate.started)
        if cancel { task.cancel() } else { session.beginEditing(in: .source) }
        gate.resume()
        #expect(await task.value == nil)
        #expect(session.renderedReadHTML.isEmpty)
    }

    @Test(
        "Measure deferred first renderer call versus cached Review rendering without a window",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DEFERRED_READ"] == "1"))
    func deferredRendererCost() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent("TestVaults", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let url = try #require(enumerator.compactMap { $0 as? URL }.first { $0.lastPathComponent == "QA Autosave A.md" })
        let original = try #require(NoteDocument.decodeUTF8PreservingBOM(Data(contentsOf: url)))
        let addition =
            "\n\n"
            + (0..<2).map { paragraph in
                (0..<256).map { "conceptualword\(paragraph)_\($0)" }.joined(separator: " ") + "."
            }.joined(separator: "\n\n") + "\n"
        for (label, source) in [("selected-standard", original), ("synthetic-long", original + addition)] {
            let document = NoteDocument(relativePath: "Fixture.md", rawContent: source)
            let semantic = MarkdownSemanticDocument(parsing: document)
            for repetition in 0..<3 {
                let session = DocumentSessionModel(key: nil)
                let cache = DocumentReadProjectionCache()
                let key = DocumentReadProjectionKey(
                    workspaceID: nil, stableTarget: "fixture", relativePath: document.relativePath, fingerprint: document.fingerprint)
                var calls = 0
                func render() async -> String {
                    calls += 1
                    return await cache.html(for: key, source: source, semantic: semantic)
                }
                session.preparePresentationMode(.livePreview)
                _ = await session.loadReadProjectionIfNeeded(using: render)
                session.beginEditing(in: .livePreview)
                _ = await session.loadReadProjectionIfNeeded(using: render)
                session.switchEditorMode(to: .source)
                _ = await session.loadReadProjectionIfNeeded(using: render)
                #expect(calls == 0 && session.renderedReadHTML.isEmpty)
                #expect(await cache.entryCount(workspaceID: nil) == 0)
                session.finishEditing()
                let coldStart = ContinuousClock.now
                let cold = await session.loadReadProjectionIfNeeded(using: render)
                let coldTime = coldStart.duration(to: .now)
                let warmStart = ContinuousClock.now
                let warm = await session.loadReadProjectionIfNeeded(using: render)
                let warmTime = warmStart.duration(to: .now)
                #expect(cold == warm && cold?.isEmpty == false)
                #expect(calls == 2)
                print(
                    "Deferred Review \(label) repetition=\(repetition) sourceBytes=\(source.utf8.count) "
                        + "Edit/Source rendererCalls=0 retainedHTMLBytes=0 "
                        + "ReviewHTMLBytes=\(cold?.utf8.count ?? 0) cold=\(coldTime) warm=\(warmTime)")
            }
        }
    }

    @MainActor
    private final class RenderGate {
        private(set) var started = false
        private var continuation: CheckedContinuation<String, Never>?

        func render() async -> String {
            await withCheckedContinuation {
                continuation = $0
                started = true
            }
        }

        func resume() {
            continuation?.resume(returning: "<p>Delayed committed projection.</p>")
            continuation = nil
        }
    }
}
