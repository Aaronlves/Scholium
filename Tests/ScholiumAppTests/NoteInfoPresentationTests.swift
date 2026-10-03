import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Note Info fixed source draft lifecycle")
@MainActor
struct NoteInfoPresentationTests {
    @Test("A failed stale apply retains all field drafts and the captured note")
    func staleApply() async {
        let context = makeContext("---\nsummary: Original\ntags: [first]\n---\nBody")
        let model = makeModel(context, apply: { _, _ in throw CancellationErrorForTest.stale })
        model.summary = "Draft"
        model.tags = "first\nsecond"
        model.apply()
        await waitForCompletion(model)
        #expect(model.context.target == context.target)
        #expect(model.summary == "Draft" && model.tags == "first\nsecond")
        #expect(model.hasChanges && model.error != nil)
    }

    @Test("Long mixed-script values reach Apply exactly and survive rejection or discard")
    func longContentDraft() async {
        let title = String(repeating: "Long Note title 研究笔记 🧪 e\u{301} / ", count: 16)
        let summary = String(repeating: "Source summary 摘要 👩‍🔬 e\u{301} / ", count: 24)
        let tag = String(repeating: "research研究", count: 20)
        let pdfPath = String(repeating: "nested研究/", count: 16) + "Original paper.pdf"
        let fileURL = URL(
            fileURLWithPath: "/nonexistent-synthetic-fixture/" + String(repeating: "directory研究/", count: 16) + "Note.md")
        let source =
            "\u{FEFF}---\r\nsummary: '\(summary)'\r\ntags: ['\(tag)']\r\npdf: '\(pdfPath)'\r\n"
            + "unknown: 'retained' # exact\r\n---\r\nBody bytes   \r\n"
        let context = makeContext(source, title: title, fileURL: fileURL)
        var submittedEdits: [String: FrontmatterEditValue] = [:]
        let model = makeModel(context) { _, edits in
            submittedEdits = edits
            throw CancellationErrorForTest.stale
        }
        #expect(model.canEditSummary && model.canEditTags)
        #expect(model.summary.utf8.elementsEqual(summary.utf8) && model.tags.utf8.elementsEqual(tag.utf8))
        #expect(model.context.title == title && model.context.fileURL.path == fileURL.path)
        #expect(model.pdfPath == pdfPath)

        let draftSummary = summary + "\nQuoted \"value\", literal \\ path\n末尾\t "
        let draftTags = [tag, String(repeating: "超长标签", count: 24), "ending space "]
        model.summary = draftSummary
        model.tags = draftTags.joined(separator: "\n")
        model.apply()
        await waitForCompletion(model)

        #expect(submittedEdits == ["summary": .string(draftSummary), "tags": .array(draftTags)])
        #expect(model.summary.utf8.elementsEqual(draftSummary.utf8))
        #expect(model.tags.utf8.elementsEqual(draftTags.joined(separator: "\n").utf8))
        #expect(model.context.document.rawContent.utf8.elementsEqual(source.utf8))
        #expect(model.hasChanges && model.error != nil)
        model.discardDraft()
        #expect(model.summary.utf8.elementsEqual(summary.utf8) && model.tags.utf8.elementsEqual(tag.utf8))
        #expect(model.context.document.rawContent.utf8.elementsEqual(source.utf8))
        #expect(!model.hasChanges && model.error == nil)
    }

    @Test("Unsupported authored tags remain unchanged and unavailable in the convenience editor")
    func unsupportedTags() {
        for tags in ["scalar", "[one, 2]", "{nested: true}", "[\"line\\npart\"]"] {
            let model = makeModel(makeContext("---\ntags: \(tags)\n---\nBody"))
            #expect(!model.canEditTags)
        }
    }

    @Test("Reload and PDF detach cannot silently discard a pending field draft")
    func pendingFieldGuard() {
        var calls = 0
        let context = makeContext("---\nsummary: Original\npdf: Paper.pdf\n---\nBody")
        let model = NoteInfoPresentationModel(
            context: context,
            reload: { _ in
                calls += 1
                return context
            },
            apply: { _, _ in
                calls += 1
                return context
            },
            attachPDF: { _ in calls += 1 }, openSource: { _ in })
        model.summary = "Unapplied"
        model.reload()
        model.detachPDF()
        model.attachPDF()
        #expect(calls == 0)
        #expect(model.summary == "Unapplied" && model.hasChanges && model.error != nil)
    }

    @Test("Closing during delayed work cannot adopt its completion")
    func delayedCompletion() async {
        let context = makeContext("---\nsummary: Original\n---\nBody")
        let model = makeModel(
            context,
            apply: { context, _ in
                try? await Task.sleep(for: .milliseconds(30))
                return makeContext("---\nsummary: Changed\n---\nBody", target: context.target)
            })
        model.summary = "Draft"
        model.apply()
        model.invalidate()
        await waitForCompletion(model)
        #expect(model.context.document.rawContent == context.document.rawContent)
        #expect(model.summary == "Draft")
    }

    @Test("The panel is a native resizable utility with no editor shortcut override")
    func nativePanel() throws {
        let context = makeContext("Body")
        let controller = NoteInfoWindowController(
            context: context,
            reload: { _ in context }, apply: { _, _ in context }, attachPDF: { _ in }, openSource: { _ in })
        let panel = try #require(controller.window as? NSPanel)
        defer { controller.close() }
        #expect(panel.styleMask.contains(.resizable) && panel.styleMask.contains(.utilityWindow))
        #expect(panel.isFloatingPanel)
        #expect(panel.contentRect(forFrameRect: panel.frame).size == NSSize(width: 360, height: 550))
        #expect(panel.contentMinSize == NSSize(width: 340, height: 360))
        #expect(DocumentNoteAction.groups.flatMap { $0 }.contains(.noteInfo))
        #expect(DocumentNoteAction.noteInfo.title(detached: true) == "Note Info…")
    }

    @Test("Origin close respects Keep Editing and explicit draft discard")
    func closeDraftGate() async {
        let context = makeContext("---\nsummary: Original\n---\nBody")
        let controller = NoteInfoWindowController(
            context: context, reload: { _ in context }, apply: { _, _ in context }, attachPDF: { _ in }, openSource: { _ in })
        controller.model.summary = "Pending draft"
        controller.discardConfirmation = { false }
        #expect(await controller.prepareForWindowClose() == false)
        #expect(controller.model.summary == "Pending draft" && controller.model.hasChanges)
        controller.discardConfirmation = { true }
        #expect(await controller.prepareForWindowClose() == true)
        #expect(controller.model.summary == "Original" && !controller.model.hasChanges)
        controller.close()
    }

    @Test("Origin close is denied while a field save is in progress")
    func closeDuringApply() async {
        let context = makeContext("---\nsummary: Original\n---\nBody")
        let controller = NoteInfoWindowController(
            context: context, reload: { _ in context },
            apply: { context, _ in
                try await Task.sleep(for: .milliseconds(30))
                return context
            }, attachPDF: { _ in }, openSource: { _ in })
        controller.model.summary = "Pending draft"
        controller.model.apply()
        #expect(await controller.prepareForWindowClose() == false)
        await waitForCompletion(controller.model)
        controller.close()
    }

    private func makeContext(
        _ source: String, target: SourceAttachmentTarget? = nil, title: String = "Synthetic Note",
        fileURL: URL = URL(fileURLWithPath: "/nonexistent-synthetic-fixture/Note.md")
    ) -> NoteInfoContext {
        let target = target ?? .init(noteID: UUID(), vaultID: UUID(), relativePath: "Note.md")
        return .init(
            target: target, title: title, document: .init(relativePath: target.relativePath, rawContent: source),
            fileURL: fileURL, canEdit: true,
            fileMetadata: .init(byteCount: source.utf8.count, creationDate: nil, modificationDate: nil))
    }

    private func makeModel(
        _ context: NoteInfoContext,
        apply: @escaping @MainActor (NoteInfoContext, [String: FrontmatterEditValue]) async throws -> NoteInfoContext = { context, _ in context }
    ) -> NoteInfoPresentationModel {
        .init(context: context, reload: { _ in context }, apply: apply, attachPDF: { _ in }, openSource: { _ in })
    }

    private func waitForCompletion(_ model: NoteInfoPresentationModel) async {
        for _ in 0..<100 where model.isWorking { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private enum CancellationErrorForTest: Error { case stale }
}
