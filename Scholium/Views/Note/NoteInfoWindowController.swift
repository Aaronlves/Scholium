import AppKit
import ScholiumContracts
import SwiftUI

struct NoteInfoContext {
    let target: SourceAttachmentTarget
    let title: String
    let document: NoteDocument
    let fileURL: URL
    let canEdit: Bool
    let fileSize: Int?
    let creationDate: Date?
    let modificationDate: Date?

    init(
        target: SourceAttachmentTarget, title: String, document: NoteDocument, fileURL: URL, canEdit: Bool,
        fileMetadata: WorkspaceFileMetadata
    ) {
        self.target = target
        self.title = title
        self.document = document
        self.fileURL = fileURL
        self.canEdit = canEdit
        fileSize = fileMetadata.byteCount
        creationDate = fileMetadata.creationDate
        modificationDate = fileMetadata.modificationDate
    }
}

/// One utility panel stays bound to its initiating Note. Its draft is never
/// retargeted by navigation, and the injected owner authorizes every mutation.
@MainActor
final class NoteInfoWindowController: NSWindowController, NSWindowDelegate {
    let model: NoteInfoPresentationModel
    var onClose: (() -> Void)?
    private weak var origin: NSWindow?
    private weak var originResponder: NSResponder?
    private var isConfirmingClose = false
    var discardConfirmation: (@MainActor () async -> Bool)?

    init(
        context: NoteInfoContext,
        reload: @escaping @MainActor (SourceAttachmentTarget) async throws -> NoteInfoContext,
        apply: @escaping @MainActor (NoteInfoContext, [String: FrontmatterEditValue]) async throws -> NoteInfoContext,
        attachPDF: @escaping @MainActor (SourceAttachmentTarget) throws -> Void,
        openSource: @escaping @MainActor (SourceAttachmentTarget) throws -> Void
    ) {
        model = NoteInfoPresentationModel(context: context, reload: reload, apply: apply, attachPDF: attachPDF, openSource: openSource)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 550),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "\(context.title) — \(ScholiumL10n.string("Note Info"))"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentMinSize = NSSize(width: 340, height: 360)
        panel.setAccessibilityIdentifier("scholium.noteInfo")
        panel.contentView = NSHostingView(rootView: NoteInfoView(model: model))
        super.init(window: panel)
        panel.delegate = self
        model.close = { [weak self] in self?.window?.performClose(nil) }
    }

    required init?(coder: NSCoder) { nil }

    func present(relativeTo window: NSWindow?) {
        origin = window
        originResponder = window?.firstResponder
        if let window, let panel = self.window {
            window.addChildWindow(panel, ordered: .above)
            var frame = panel.frame
            frame.origin = NSPoint(x: window.frame.maxX - frame.width, y: window.frame.maxY - frame.height - 45)
            let visible = window.screen?.visibleFrame ?? window.frame
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            panel.setFrame(frame, display: false)
        } else {
            self.window?.center()
        }
        showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.isWorking else { return false }
        guard model.hasChanges else { return true }
        Task { @MainActor [weak self, weak sender] in
            guard let self, await self.prepareForWindowClose() else { return }
            sender?.close()
        }
        return false
    }

    /// Native origin close and application termination use this same gate;
    /// unapplied panel drafts are never silently discarded by teardown.
    func prepareForWindowClose() async -> Bool {
        guard !model.isWorking, !isConfirmingClose else {
            window?.makeKeyAndOrderFront(nil)
            return false
        }
        guard model.hasChanges else { return true }
        guard let panel = window, panel.attachedSheet == nil else { return false }
        isConfirmingClose = true
        defer { isConfirmingClose = false }
        panel.makeKeyAndOrderFront(nil)
        let discards: Bool
        if let discardConfirmation { discards = await discardConfirmation() } else { discards = await confirmDiscard(in: panel) }
        guard discards else { return false }
        model.discardDraft()
        return true
    }

    private func confirmDiscard(in panel: NSWindow) async -> Bool {
        let alert = NSAlert()
        alert.messageText = ScholiumL10n.string("Discard Note Info changes?")
        alert.informativeText = ScholiumL10n.string("Your Markdown has not changed. The unapplied fields in this panel will be discarded.")
        alert.addButton(withTitle: ScholiumL10n.string("Keep Editing"))
        alert.addButton(withTitle: ScholiumL10n.string("Discard Changes"))
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: panel) { result in
                continuation.resume(returning: result == .alertSecondButtonReturn)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.invalidate()
        if let panel = window { origin?.removeChildWindow(panel) }
        if origin?.isVisible == true {
            origin?.makeKeyAndOrderFront(nil)
            if let responder = originResponder { origin?.makeFirstResponder(responder) }
        }
        origin = nil
        originResponder = nil
        discardConfirmation = nil
        onClose?()
    }
}

@MainActor
final class NoteInfoPresentationModel: ObservableObject {
    @Published private(set) var context: NoteInfoContext
    @Published var summary: String
    @Published var tags: String
    @Published private(set) var error: String?
    @Published private(set) var isWorking = false
    var close: (() -> Void)?
    private let reloadAction: @MainActor (SourceAttachmentTarget) async throws -> NoteInfoContext
    private let applyAction: @MainActor (NoteInfoContext, [String: FrontmatterEditValue]) async throws -> NoteInfoContext
    private let attachAction: @MainActor (SourceAttachmentTarget) throws -> Void
    private let sourceAction: @MainActor (SourceAttachmentTarget) throws -> Void
    private var task: Task<Void, Never>?
    private var valid = true

    init(
        context: NoteInfoContext,
        reload: @escaping @MainActor (SourceAttachmentTarget) async throws -> NoteInfoContext,
        apply: @escaping @MainActor (NoteInfoContext, [String: FrontmatterEditValue]) async throws -> NoteInfoContext,
        attachPDF: @escaping @MainActor (SourceAttachmentTarget) throws -> Void,
        openSource: @escaping @MainActor (SourceAttachmentTarget) throws -> Void
    ) {
        self.context = context
        summary = Self.summary(in: context.document)
        tags = Self.tags(in: context.document)
        reloadAction = reload
        applyAction = apply
        attachAction = attachPDF
        sourceAction = openSource
    }

    var pdfPath: String? { try? PDFNoteBinding.path(in: context.document) }
    var pdfBindingInvalid: Bool {
        do {
            _ = try PDFNoteBinding.path(in: context.document)
            return false
        } catch { return true }
    }
    var hasChanges: Bool { summary != Self.summary(in: context.document) || tags != Self.tags(in: context.document) }

    var canEditSummary: Bool { canEdit(key: "summary", value: .string(Self.summary(in: context.document))) }
    var canEditTags: Bool {
        let value = context.document.parsedFrontmatter["tags"]
        guard value == nil || Self.stringTags(value) != nil else { return false }
        return canEdit(key: "tags", value: .array(Self.stringTags(value) ?? []))
    }
    var canChangePDF: Bool {
        !pdfBindingInvalid && canEdit(key: "pdf", value: pdfPath.map(FrontmatterEditValue.string) ?? .string(""))
    }

    private func canEdit(key: String, value: FrontmatterEditValue) -> Bool {
        guard context.canEdit, context.document.frontmatterState != .malformed else { return false }
        return (try? NoteInfoMetadataPlanner.plan(document: context.document, edits: [key: value])) != nil
            || (try? context.document.applying(.frontmatter([key: value]), timestampKey: nil)) != nil
    }

    func apply() {
        var edits: [String: FrontmatterEditValue] = [:]
        if summary != Self.summary(in: context.document), canEditSummary {
            edits["summary"] = summary.isEmpty ? .remove : .string(summary)
        }
        if tags != Self.tags(in: context.document), canEditTags {
            let values = tags.components(separatedBy: .newlines).filter { !$0.isEmpty }
            edits["tags"] = values.isEmpty ? .remove : .array(values)
        }
        guard !edits.isEmpty else { return }
        perform { [self] in try await applyAction(context, edits) }
    }

    func reload() {
        guard !hasChanges else {
            error = ScholiumL10n.string("Apply or discard your field changes before reloading Note Info.")
            return
        }
        perform { [self] in try await reloadAction(context.target) }
    }

    func detachPDF() {
        guard canChangePDF else { return }
        guard !hasChanges else {
            error = ScholiumL10n.string("Apply or discard your field changes before changing the PDF.")
            return
        }
        perform { [self] in try await applyAction(context, ["pdf": .remove]) }
    }

    func attachPDF() {
        guard canChangePDF, !isWorking else { return }
        guard !hasChanges else {
            error = ScholiumL10n.string("Apply or discard your field changes before changing the PDF.")
            return
        }
        do { try attachAction(context.target) } catch { self.error = PDFReaderPresentationError.message(error) }
    }

    func openSource() {
        do { try sourceAction(context.target) } catch { self.error = PDFReaderPresentationError.message(error) }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> NoteInfoContext) {
        guard valid, !isWorking else { return }
        isWorking = true
        error = nil
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isWorking = false
                self.task = nil
            }
            guard self.valid, !Task.isCancelled else { return }
            do {
                let refreshed = try await operation()
                guard self.valid, !Task.isCancelled, refreshed.target == self.context.target else { return }
                self.context = refreshed
                self.discardDraft()
            } catch is CancellationError { return } catch {
                guard self.valid else { return }
                self.error = PDFReaderPresentationError.message(error)
            }
        }
    }

    func discardDraft() {
        summary = Self.summary(in: context.document)
        tags = Self.tags(in: context.document)
        error = nil
    }

    func invalidate() {
        valid = false
        task?.cancel()
        task = nil
        close = nil
    }

    private static func summary(in document: NoteDocument) -> String {
        if case .string(let value) = document.parsedFrontmatter["summary"] { return value }
        return ""
    }
    private static func tags(in document: NoteDocument) -> String { (stringTags(document.parsedFrontmatter["tags"]) ?? []).joined(separator: "\n") }
    private static func stringTags(_ value: YAMLValue?) -> [String]? {
        guard case .array(let values) = value else { return nil }
        var strings: [String] = []
        for value in values {
            guard case .string(let string) = value, !string.isEmpty, !string.contains(where: \.isNewline) else { return nil }
            strings.append(string)
        }
        return strings
    }
}

private struct NoteInfoView: View {
    @ObservedObject var model: NoteInfoPresentationModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Note") { Text(model.context.title).textSelection(.enabled) }
                    LabeledContent("Summary") {
                        TextField("Summary", text: $model.summary, axis: .vertical)
                            .lineLimit(2...6).disabled(!model.canEditSummary || model.isWorking)
                            .accessibilityIdentifier("scholium.noteInfo.summary")
                    }
                    LabeledContent("Tags") {
                        TextField("One tag per line", text: $model.tags, axis: .vertical)
                            .lineLimit(2...5).disabled(!model.canEditTags || model.isWorking)
                            .accessibilityIdentifier("scholium.noteInfo.tags")
                    }
                    Text("Fields edit authored YAML. Other properties remain editable in Source.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Source", action: model.openSource)
                }
                Section("PDF") {
                    if let path = model.pdfPath {
                        Text(path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Replace PDF…", action: model.attachPDF)
                            Button("Detach PDF", action: model.detachPDF)
                        }.disabled(!model.canChangePDF || model.isWorking)
                    } else {
                        Text(
                            verbatim: model.pdfBindingInvalid
                                ? ScholiumL10n.string("The pdf property needs a valid string path.") : ScholiumL10n.string("No PDF attached.")
                        )
                        .foregroundStyle(.secondary)
                        Button("Attach PDF…", action: model.attachPDF).disabled(!model.canChangePDF || model.isWorking)
                    }
                    Text("Detaching keeps the managed file and its annotations.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("File Information") {
                    LabeledContent("Where") { Text(model.context.fileURL.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    if let bytes = model.context.fileSize {
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    }
                    if let date = model.context.creationDate { LabeledContent("Created") { Text(date, format: .dateTime) } }
                    if let date = model.context.modificationDate { LabeledContent("Modified") { Text(date, format: .dateTime) } }
                }
            }.formStyle(.grouped)
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.primary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                    .accessibilityIdentifier("scholium.noteInfo.error")
            }
            HStack {
                Button("Reload", action: model.reload).disabled(model.isWorking || model.hasChanges)
                if model.hasChanges { Button("Discard Changes", action: model.discardDraft).disabled(model.isWorking) }
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small).accessibilityLabel("Applying Note Info") }
                Button("Apply", action: model.apply).disabled(!model.hasChanges || model.isWorking)
                    .accessibilityIdentifier("scholium.noteInfo.apply")
                Button("Close") { model.close?() }.keyboardShortcut(.cancelAction).disabled(model.isWorking)
            }.padding()
        }
    }
}
