import AppKit
import ScholiumContracts
import SwiftUI

private struct ScholiumFileCreationCommandContent: View {
    let commandRevision: UInt64
    let storageReady: Bool
    let fileOpening: MarkdownFileOpeningController
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var appState: WindowModel?

    var body: some View {
        Button("New Note") {
            guard let appState else { return }
            appState.libraryMutationController.requestUntitledNoteCreation(in: appState.selectedLibraryCreationFolder)
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.newNote)
        .disabled(
            appState?.workspaceAssignment == nil
                || appState?.noteSourceScope != .library
                || appState?.isDetachedDocumentWindow == true
                || appState?.libraryMutationController.isCreatingNote == true
        )
        Button("New Window") {
            openWindow(
                id: "scholium-main",
                value: TriptychWindowRoute(triptychID: appState?.workspaceAssignment?.id)
            )
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.newWindow)
        .disabled(!storageReady)
        Button("New Triptych…") {
            openWindow(
                id: "scholium-bootstrap",
                value: BootstrapWindowRoute(purpose: .newTriptych)
            )
        }
        .scholiumActivationPointer()
        .disabled(!storageReady)
        Divider()
        Button("Open Markdown…") { fileOpening.chooseFiles() }
            .scholiumKeyboardShortcut(.openMarkdown)
        Menu("Open Triptych") {
            ForEach(appState?.registeredTriptychs ?? []) { assignment in
                Button(triptychCommandLabel(assignment)) {
                    openWindow(
                        id: "scholium-main",
                        value: TriptychWindowRoute(triptychID: assignment.id)
                    )
                }
                .scholiumActivationPointer()
            }
        }
        .scholiumActivationPointer()
        .disabled(appState?.registeredTriptychs.isEmpty != false)
    }

    private func triptychCommandLabel(_ assignment: TriptychAssignment) -> String {
        let registered = appState?.registeredTriptychs ?? []
        let duplicates = registered.filter {
            $0.triptych.name.caseInsensitiveCompare(assignment.triptych.name) == .orderedSame
        }
        guard duplicates.count > 1,
            let works = assignment.vault(for: .output)
        else {
            return assignment.triptych.name
        }
        let parent = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            .deletingLastPathComponent().lastPathComponent
        return "\(assignment.triptych.name) — \(parent)"
    }
}

private struct ScholiumCloseTabCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?

    var body: some View {
        if let external {
            Button("Close Window") { external.closeWindow() }
                .scholiumKeyboardShortcut(.closeTab).disabled(!external.canRequestClose)
        } else {
            Button(ScholiumL10n.dynamicString(appState?.isDetachedDocumentWindow == true ? "Close Window" : "Close Tab")) {
                if appState?.isDetachedDocumentWindow == true {
                    appState?.nativeWindowCoordinator?.requestNativeClose()
                    return
                }
                guard let id = appState?.documentTabController.selectedTabID else { return }
                appState?.closeDocumentTab(withID: id)
            }
            .scholiumKeyboardShortcut(.closeTab)
            .disabled(appState?.documentTabController.selectedTabID == nil)
        }
    }
}

private struct ScholiumFileDocumentCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?
    private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions }

    var body: some View {
        if let external {
            Button("Save") { Task { await external.save() } }
                .scholiumKeyboardShortcut(.save).disabled(!external.canSave)
            Button("Import to Triptych…") { external.showsImport = true }.disabled(!external.canPresentImport)
            Button("Reveal Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([external.originalURL]) }
            Divider()
        } else {
            Button("Save") {
                guard let appState, let document = appState.documentController.selectedDocument else { return }
                let session = appState.documentController.session(for: document.editingTarget)
                Task { await appState.documentController.persistEditingSource(session: session, target: document.editingTarget) }
            }
            .scholiumKeyboardShortcut(.save)
            .disabled(appState?.currentEditorActions?.isComposing != false)
            Divider()
        }
        Button("Import Markdown…") { appState?.showMarkdownImporter = true }
            .scholiumActivationPointer()
            .disabled(appState?.workspaceAssignment == nil || appState?.isDetachedDocumentWindow == true)
        Divider()
        Button("Duplicate Note…") {
            guard let target = appState?.fileCommandSingleNoteTarget else { return }
            appState?.noteFileRequest = .duplicate(target)
        }
        .scholiumActivationPointer()
        .disabled(appState?.fileCommandSingleNoteTarget == nil)
        Button("Move Note…") {
            if let targets = appState?.focusedLibraryMutationTargets {
                appState?.requestLibraryBatchMove(targets)
            } else if let target = appState?.fileCommandSingleNoteTarget {
                appState?.noteFileRequest = .move(target)
            }
        }
        .scholiumActivationPointer()
        .disabled(appState?.canPerformFileSelectionMutation != true)
        Button("Export Note…") { appState?.requestCurrentNoteExport() }
            .scholiumActivationPointer()
            .disabled(appState?.canPerformNoteAction(.export) != true)
        Divider()
        Button("Attach a Copy…") { editorActions?.attachDocumentCopy() }
            .scholiumActivationPointer()
            .disabled(editorActions?.canAttachDocument != true)
        Button("Reference Original…") {
            editorActions?.referenceOriginalDocument()
        }
        .scholiumActivationPointer()
        .disabled(editorActions?.canAttachDocument != true)
        Divider()
        Button("Reveal Note in Finder") { appState?.performNoteAction(.revealInFinder) }
            .scholiumActivationPointer()
            .disabled(appState?.canPerformNoteAction(.revealInFinder) != true)
        Button("Reveal Current Vault in Finder") { appState?.revealVaultInFinder() }
            .scholiumActivationPointer()
            .disabled(appState?.vaultConfig == nil)
        Divider()
        Button("Move to Trash…") {
            if let targets = appState?.focusedLibraryMutationTargets {
                appState?.requestLibraryBatchTrash(targets)
            } else {
                appState?.requestCurrentNoteSystemTrash()
            }
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.moveToTrash)
        .disabled(appState?.canPerformFileSelectionMutation != true)
    }
}

private struct ScholiumPasteboardCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?
    private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions ?? external?.editorActions }

    var body: some View {
        Button("Copy Note Link") { appState?.performNoteAction(.copyLink) }
            .scholiumActivationPointer()
            .disabled(appState?.canPerformNoteAction(.copyLink) != true)
        Button("Paste as Markdown") {
            guard let payload = markdownPasteboardPayload() else { return }
            editorActions?.performWithArgument(.pasteMarkdown, payload)
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.pasteMarkdown)
        .disabled(editorActions?.isAvailable(.pasteMarkdown) != true)
        Divider()
        Menu("Find") {
            Button("Find…") { if let external { external.performFind(.present) } else { appState?.presentCurrentDocumentFind() } }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.find)
                .disabled(appState?.documentController.canFindSelectedDocument != true && external?.snapshot == nil)
            Button("Find and Replace…") {
                if let external { external.documentFind.presentReplacement() } else { appState?.documentController.presentReplacementFindForSelectedDocument() }
            }
            .scholiumActivationPointer()
            .disabled(appState?.documentController.canReplaceInSelectedDocument != true && external?.mode.editorMode == nil)
            Divider()
            Button("Find Next") { if let external { external.performFind(.next) } else { appState?.documentController.performSelectedDocumentFind(.next) } }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.findNext)
                .disabled(appState?.documentController.canFindSelectedDocument != true && external?.snapshot == nil)
            Button("Find Previous") {
                if let external { external.performFind(.previous) } else { appState?.documentController.performSelectedDocumentFind(.previous) }
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.findPrevious)
            .disabled(appState?.documentController.canFindSelectedDocument != true && external?.snapshot == nil)
            Button("Use Selection for Find") {
                if let external { external.performFind(.useSelection) } else { appState?.documentController.performSelectedDocumentFind(.useSelection) }
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.useSelectionForFind)
            .disabled(appState?.documentController.canFindSelectedDocument != true && external?.snapshot == nil)
        }
        .scholiumActivationPointer()
    }

    private func markdownPasteboardPayload() -> String? {
        let pasteboard = NSPasteboard.general
        let plainText = pasteboard.string(forType: .string) ?? ""
        let html = pasteboard.string(forType: .html)
        guard !plainText.isEmpty || html?.isEmpty == false else { return nil }
        var payload = ["plainText": plainText]
        if let html, !html.isEmpty { payload["html"] = html }
        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload)
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct ScholiumTextFormattingCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?
    private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions ?? external?.editorActions }

    var body: some View {
        Button("Bold") { editorActions?.perform(.bold) }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.bold)
            .disabled(editorActions?.isAvailable(.bold) != true)
        Button("Italic") { editorActions?.perform(.emphasis) }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.italic)
            .disabled(editorActions?.isAvailable(.emphasis) != true)
        Button("Strikethrough") { editorActions?.perform(.strikethrough) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.strikethrough) != true)
        Button("Highlight") { editorActions?.perform(.highlight) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.highlight) != true)
        Button("Inline Code") { editorActions?.perform(.inlineCode) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.inlineCode) != true)
        Divider()
        Menu("Heading") {
            Button("Paragraph") { editorActions?.perform(.paragraph) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.paragraph) != true)
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") {
                    editorActions?.perform(headingCommand(level))
                }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(headingCommand(level)) != true)
            }
        }
        .scholiumActivationPointer()
        Menu("Lists") {
            Button("Bulleted List") { editorActions?.perform(.bulletList) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.bulletList) != true)
            Button("Numbered List") { editorActions?.perform(.numberedList) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.numberedList) != true)
            Button("Task List") { editorActions?.perform(.taskList) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.taskList) != true)
            Button("Toggle Task") { editorActions?.perform(.toggleTask) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.toggleTask) != true)
        }
        .scholiumActivationPointer()
        Button("Block Quotation") { editorActions?.perform(.blockQuotation) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.blockQuotation) != true)
        Button("Fenced Code") { editorActions?.perform(.fencedCode) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.fencedCode) != true)
        Divider()
        Menu("Table") {
            Button("Insert Row Before") { editorActions?.perform(.tableInsertRowBefore) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableInsertRowBefore) != true)
            Button("Insert Row After") { editorActions?.perform(.tableInsertRowAfter) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableInsertRowAfter) != true)
            Button("Delete Row") { editorActions?.perform(.tableDeleteRow) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableDeleteRow) != true)
            Divider()
            Button("Insert Column Before") { editorActions?.perform(.tableInsertColumnBefore) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableInsertColumnBefore) != true)
            Button("Insert Column After") { editorActions?.perform(.tableInsertColumnAfter) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableInsertColumnAfter) != true)
            Button("Delete Column") { editorActions?.perform(.tableDeleteColumn) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableDeleteColumn) != true)
            Divider()
            Button("Align Left") { editorActions?.perform(.tableAlignLeft) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableAlignLeft) != true)
            Button("Align Center") { editorActions?.perform(.tableAlignCenter) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableAlignCenter) != true)
            Button("Align Right") { editorActions?.perform(.tableAlignRight) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.tableAlignRight) != true)
        }
        .scholiumActivationPointer()
    }

    private func headingCommand(_ level: Int) -> MarkdownEditorCommand {
        switch level {
        case 1: .heading1
        case 2: .heading2
        case 3: .heading3
        case 4: .heading4
        case 5: .heading5
        default: .heading6
        }
    }
}

private struct ScholiumInsertCommandContent: View {
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?
    let commandRevision: UInt64
    private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions ?? external?.editorActions }

    var body: some View {
        Button("Link") { editorActions?.perform(.standardLink) }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.insertLink)
            .disabled(editorActions?.isAvailable(.standardLink) != true)
        Button("Wikilink") { editorActions?.perform(.wikilink) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.wikilink) != true)
        Button("Annotated Wikilink") { editorActions?.perform(.annotatedWikilink) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.annotatedWikilink) != true)
        Divider()
        Button("Footnote") { editorActions?.perform(.insertFootnote) }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.insertFootnote)
            .disabled(editorActions?.isAvailable(.insertFootnote) != true)
        Button("Inline Footnote") { editorActions?.perform(.insertInlineFootnote) }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.insertInlineFootnote)
            .disabled(editorActions?.isAvailable(.insertInlineFootnote) != true)
        Divider()
        Button("Import Image…") { editorActions?.importImage() }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Button("Index Image…") { editorActions?.indexImage() }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Divider()
        Button("Table") { editorActions?.perform(.insertTable) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.insertTable) != true)
        Button("Thematic Break") { editorActions?.perform(.thematicBreak) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.thematicBreak) != true)
        Divider()
        Button("Markdown Comment") { editorActions?.perform(.markdownComment) }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.markdownComment) != true)
        Menu("Callout") {
            Button {
                editorActions?.perform(.calloutOrient)
            } label: {
                Text("Orientation", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutOrient) != true)
            Button {
                editorActions?.perform(.calloutCite)
            } label: {
                Text("Source", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutCite) != true)
            Button {
                editorActions?.perform(.calloutConnect)
            } label: {
                Text("Connections", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutConnect) != true)
            Button {
                editorActions?.perform(.calloutState)
            } label: {
                Text("Statement", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutState) != true)
            Button {
                editorActions?.perform(.calloutIllustrate)
            } label: {
                Text("Illustration", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutIllustrate) != true)
            Button {
                editorActions?.perform(.calloutQuote)
            } label: {
                Text("Quotation", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutQuote) != true)
            Button {
                editorActions?.perform(.calloutFlag)
            } label: {
                Text("Caution", tableName: "WebKitInterface", bundle: .module)
            }
            .scholiumActivationPointer()
            .disabled(editorActions?.isAvailable(.calloutFlag) != true)
        }
        .scholiumActivationPointer()
    }
}

private struct ScholiumViewCommandContent: View {
    let commandRevision: UInt64
    @ObservedObject private var chatSidebarPreferences = ChatSidebarPreferences.shared
    @FocusedObject private var appState: WindowModel?
    @FocusedObject private var external: ExternalMarkdownWindowModel?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions ?? external?.editorActions }

    var body: some View {
        Button("Back") {
            appState?.navigateDocumentHistory(.back)
        }
        .scholiumActivationPointer()
        .disabled(appState?.documentNavigationHistoryController.canGoBack != true)
        Button("Forward") {
            appState?.navigateDocumentHistory(.forward)
        }
        .scholiumActivationPointer()
        .disabled(appState?.documentNavigationHistoryController.canGoForward != true)
        Divider()
        Button("Advanced Search…") { searchActions?.advanced() }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.searchResearch)
            .disabled(searchActions == nil)
        Button("Go to Frontmatter") {
            editorActions?.goToFrontmatter()
        }
        .scholiumKeyboardShortcut(.goToFrontmatter)
        .disabled(editorActions?.canEditFrontmatter != true || editorActions?.isComposing == true)
        Divider()
        Toggle(
            "Focus Layout",
            isOn: Binding(
                get: { appState?.shellState.isFocusLayoutActive == true },
                set: { _ in workspaceWindowActions?.toggleFocusLayout() }
            )
        )
        .scholiumKeyboardShortcut(.toggleFocusLayout)
        .disabled(workspaceWindowActions?.canToggleFocusLayout() != true || editorActions?.isComposing == true)
        Divider()
        Button(
            ScholiumL10n.dynamicString(
                appState?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar"
            )
        ) {
            guard let appState else { return }
            workspaceWindowActions?.setLibraryVisible(!appState.sidebarVisible)
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.toggleLibrary)
        .disabled(workspaceWindowActions?.canUseSidebar() != true)
        Button("Library") {
            workspaceWindowActions?.activateSidebar(.library)
        }
        .disabled(workspaceWindowActions?.canUseSidebar() != true)
        if chatSidebarPreferences.isEnabled {
            Button("Chat") {
                workspaceWindowActions?.activateSidebar(.chat)
            }
            .disabled(workspaceWindowActions?.canUseSidebar() != true || appState?.canPresentChat != true)
        }
        Button(
            ScholiumL10n.dynamicString(
                appState?.researchInspectorVisible == true
                    ? "Hide Research Inspector"
                    : "Show Research Inspector"
            )
        ) {
            guard let appState else { return }
            workspaceWindowActions?.setResearchInspectorVisible(
                !appState.researchInspectorVisible
            )
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.toggleResearchInspector)
        .disabled(
            workspaceWindowActions == nil || appState?.canToggleResearchInspector != true
                || appState?.shellState.isFocusLayoutLockedByFullScreen == true
        )
        Divider()
        Button(
            ScholiumL10n.dynamicString(
                (appState?.presentedDocumentMode ?? external?.mode) == .read ? "Edit" : "Review"
            )
        ) {
            guard let destination = reviewEditDestination else { return }
            if let external { external.selectMode(destination) } else { appState?.requestDocumentMode(destination) }
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.toggleReviewEdit)
        .disabled(reviewEditDestination == nil || editorActions?.isComposing == true)
        Menu("Document Mode") {
            Toggle("Review", isOn: documentModeSelection(.read))
                .scholiumActivationPointer()
                .disabled(!canSelectDocumentMode(.read))
            Toggle("Edit", isOn: documentModeSelection(.livePreview))
                .scholiumActivationPointer()
                .disabled(!canSelectDocumentMode(.livePreview))
            if appState?.isDetachedDocumentWindow != true {
                Toggle("Source", isOn: documentModeSelection(.source))
                    .scholiumActivationPointer()
                    .scholiumKeyboardShortcut(.showSource)
                    .disabled(!canSelectDocumentMode(.source))
            }
        }
        .scholiumActivationPointer()
        Divider()
        Menu("Document Text Size") {
            Button("Increase Text Size") {
                setDocumentTextScale(documentTextScale + ScholiumMetrics.Document.textScaleStep)
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.increaseTextSize)
            .disabled(
                !hasDocument
                    || documentTextScale == ScholiumMetrics.Document.maximumTextScale
            )
            Button("Decrease Text Size") {
                setDocumentTextScale(documentTextScale - ScholiumMetrics.Document.textScaleStep)
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.decreaseTextSize)
            .disabled(
                !hasDocument
                    || documentTextScale == ScholiumMetrics.Document.minimumTextScale
            )
            Toggle("Actual Size (100%)", isOn: documentTextScaleSelection(ScholiumMetrics.Document.defaultTextScale))
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.actualTextSize)
                .disabled(
                    !hasDocument
                        || documentTextScale == ScholiumMetrics.Document.defaultTextScale
                )
            Divider()
            Toggle("150%", isOn: documentTextScaleSelection(1.5))
                .scholiumActivationPointer()
                .disabled(!hasDocument || documentTextScale == 1.5)
            Toggle("200%", isOn: documentTextScaleSelection(ScholiumMetrics.Document.maximumTextScale))
                .scholiumActivationPointer()
                .disabled(
                    !hasDocument
                        || documentTextScale == ScholiumMetrics.Document.maximumTextScale
                )
        }
        .scholiumActivationPointer()
        Menu("Appearance") {
            Toggle("Use System Appearance", isOn: colorSchemeSelection(.system))
                .scholiumActivationPointer()
                .disabled(appState == nil && external == nil)
            Toggle("Light", isOn: colorSchemeSelection(.light))
                .scholiumActivationPointer()
                .disabled(appState == nil && external == nil)
            Toggle("Dark", isOn: colorSchemeSelection(.dark))
                .scholiumActivationPointer()
                .disabled(appState == nil && external == nil)
        }
        .scholiumActivationPointer()
    }

    private var hasDocument: Bool { external?.snapshot != nil || appState?.currentNote != nil }
    private var documentTextScale: Double { external?.documentTextScale ?? appState?.documentTextScale ?? ScholiumMetrics.Document.defaultTextScale }

    private func setDocumentTextScale(_ scale: Double) {
        if let external { external.setDocumentTextScale(scale) } else { appState?.setDocumentTextScale(scale) }
    }

    private func setColorScheme(_ scheme: WindowColorSchemeChoice) {
        if let external { external.colorScheme = scheme } else { appState?.colorScheme = scheme }
    }

    private func canSelectDocumentMode(_ mode: NotePresentationMode) -> Bool {
        if let external { return external.canSelectMode(mode) }
        guard hasDocument, editorActions?.isComposing != true else { return false }
        return mode == .read || appState?.canEditCurrentNote == true
    }

    private func documentModeSelection(_ mode: NotePresentationMode) -> Binding<Bool> {
        Binding(
            get: { hasDocument && (external?.mode ?? appState?.presentedDocumentMode) == mode },
            set: { selected in
                guard selected, canSelectDocumentMode(mode) else { return }
                if let external { external.selectMode(mode) } else { appState?.requestDocumentMode(mode) }
            }
        )
    }

    private func documentTextScaleSelection(_ scale: Double) -> Binding<Bool> {
        Binding(
            get: { hasDocument && documentTextScale == scale },
            set: { selected in if selected && hasDocument { setDocumentTextScale(scale) } }
        )
    }

    private func colorSchemeSelection(_ scheme: WindowColorSchemeChoice) -> Binding<Bool> {
        Binding(
            get: { (external?.colorScheme ?? appState?.colorScheme) == scheme },
            set: { selected in if selected { setColorScheme(scheme) } }
        )
    }

    private var reviewEditDestination: NotePresentationMode? {
        if let external, external.snapshot != nil, !external.isBusy {
            let destination: NotePresentationMode = external.mode == .read ? .livePreview : .read
            return external.canSelectMode(destination) ? destination : nil
        }
        guard let appState, appState.currentNote != nil else { return nil }
        switch appState.presentedDocumentMode {
        case .read:
            return appState.canEditCurrentNote ? .livePreview : nil
        case .livePreview, .source:
            return .read
        }
    }
}

private struct ScholiumResearchCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions

    var body: some View {
        Button("Find Related Material") {
            appState?.performPassageAction(.relatedMaterial)
        }
        .disabled(appState?.currentNote == nil || appState?.isDetachedDocumentWindow == true || appState?.shellState.isFocusLayoutLockedByFullScreen == true)
        Button("Find Writing References") {
            guard let appState else { return }
            appState.researchController.selectInspectorMode(.related)
            workspaceWindowActions?.setResearchInspectorVisible(true)
            appState.findRelatedMaterials()
        }
        .scholiumKeyboardShortcut(.findWritingReferences)
        .disabled(appState?.canFindWritingReferences != true || appState?.shellState.isFocusLayoutLockedByFullScreen == true)
        Divider()
        Button("Add Note to Chat") { appState?.performNoteAction(.addToChat) }
            .scholiumActivationPointer()
            .disabled(appState?.canPerformNoteAction(.addToChat) != true)
        Button("Add Selection to Chat") {
            Task {
                if await appState?.addCurrentSelectionToChat() == true,
                    appState?.shellState.sidebarContent != .chat || appState?.shellState.libraryVisible != true
                {
                    workspaceWindowActions?.activateSidebar(.chat)
                }
            }
        }
        .scholiumKeyboardShortcut(.addSelectionToChat)
        .disabled(appState?.currentNote == nil || appState?.canPresentChat != true || appState?.chatController == nil)
        if let controller = appState?.chatController {
            AgentChatStopCommand(controller: controller)
        }
        Divider()
        ForEach([DocumentPassageAction.copyLink, .extract, .move, .copy], id: \.rawValue) { action in
            Button(action.title) { appState?.performPassageAction(action) }
                .disabled(appState?.canEditCurrentNote != true)
        }
        Button("Merge into Another Note…") { appState?.requestMergeCurrentNote() }
            .disabled(appState?.canMergeCurrentNote != true)
        Divider()
        Button("Changes…") {
            appState?.presentationRouter.present(.documentChanges(scope: .all))
        }
        .disabled(appState?.windowWorkspaceController.activeCapabilities == nil)
    }
}

private struct ScholiumWindowCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?

    var body: some View {
        Menu("Document Tabs") {
            let owner = appState
            Picker(
                "Document Tabs",
                selection: Binding<UUID?>(
                    get: { owner?.documentTabController.selectedTabID },
                    set: { selected in
                        if let selected { owner?.selectDocumentTab(withID: selected) }
                    }
                )
            ) {
                ForEach(owner?.documentTabController.tabs ?? []) { tab in
                    Text(verbatim: tab.title).tag(Optional(tab.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .menuActionDismissBehavior(.enabled)
        }
        .disabled(appState?.documentTabController.tabs.isEmpty != false)
        Button("Next Tab") { appState?.selectAdjacentDocumentTab(offset: 1) }
            .scholiumKeyboardShortcut(.nextTab)
            .disabled((appState?.documentTabController.tabs.count ?? 0) < 2)
        Button("Previous Tab") { appState?.selectAdjacentDocumentTab(offset: -1) }
            .scholiumKeyboardShortcut(.previousTab)
            .disabled((appState?.documentTabController.tabs.count ?? 0) < 2)
        Divider()
        Button(appState?.isDetachedDocumentWindow == true ? "Move to Main Window" : "Move to Separate Window") {
            guard let appState else { return }
            if appState.isDetachedDocumentWindow { appState.requestMoveDocumentBack() } else { appState.requestMoveDocumentToWindow() }
        }
        .disabled(appState?.documentTabController.selectedTabID == nil)
    }
}

private struct ScholiumAttentionCommandContent: View {
    let commandRevision: UInt64
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions

    var body: some View {
        Button("Notifications") {
            workspaceWindowActions?.showPreferredAttention()
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.showAttention)
        .disabled(workspaceWindowActions?.canShowAttention() != true)
    }
}

#if DEBUG
    private struct ScholiumQACommandContent: View {
        let commandRevision: UInt64
        @FocusedObject private var appState: WindowModel?
        @FocusedObject private var external: ExternalMarkdownWindowModel?
        private var editorActions: ScholiumFocusedEditorActions? { appState?.currentEditorActions ?? external?.editorActions }

        var body: some View {
            if qaEditorFaultsAreEnabled {
                Button("Simulate Editor Process Termination") {
                    guard let documentID = editorActions?.documentID else { return }
                    DistributedNotificationCenter.default().postNotificationName(
                        Notification.Name("com.scholium.qa.simulate-editor-process-termination"),
                        object: nil,
                        userInfo: ["documentID": documentID],
                        deliverImmediately: true
                    )
                }
                .scholiumActivationPointer()
                .keyboardShortcut("w", modifiers: [.command, .option, .control])
                .disabled(editorActions == nil)
            }
            if qaEditorFaultsAreEnabled && qaOperationProofsAreEnabled {
                Divider()
            }
            if qaOperationProofsAreEnabled {
                Button("Present Operation Issue Proof") {
                    appState?.reportOperationIssue(
                        "QA operation warning",
                        kind: .warning,
                        detail:
                            "The file is preserved. This synthetic warning checks that a long explanation remains readable beside its operation and offers only the valid refresh action.",
                        offersRefresh: true
                    )
                }
                .scholiumActivationPointer()
                .disabled(appState == nil)
            }
        }

        private var qaEditorFaultsAreEnabled: Bool {
            Bundle.main.bundleIdentifier == "com.scholium.qa"
                && ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults")
        }

        private var qaOperationProofsAreEnabled: Bool {
            Bundle.main.bundleIdentifier == "com.scholium.qa"
                && ProcessInfo.processInfo.arguments.contains(
                    "--scholium-operation-proofs"
                )
        }
    }
#endif

struct ScholiumCommands: Commands {
    let fileOpening: MarkdownFileOpeningController
    @FocusedValue(\.scholiumApplicationBootstrapStatus)
    private var applicationBootstrapStatus
    @FocusedObject private var commandObservation: WindowCommandObservation?

    var body: some Commands {
        let commandRevision = commandObservation?.revision ?? 0
        let storageReady = applicationBootstrapStatus?.isReady == true
        let fileCreationCommand = ScholiumFileCreationCommandContent(
            commandRevision: commandRevision,
            storageReady: storageReady,
            fileOpening: fileOpening
        )
        let fileDocumentCommand = ScholiumFileDocumentCommandContent(commandRevision: commandRevision)
        let pasteboardCommand = ScholiumPasteboardCommandContent(commandRevision: commandRevision)
        let textFormattingCommand = ScholiumTextFormattingCommandContent(commandRevision: commandRevision)
        let insertCommand = ScholiumInsertCommandContent(commandRevision: commandRevision)
        let viewCommand = ScholiumViewCommandContent(commandRevision: commandRevision)
        let attentionCommand = ScholiumAttentionCommandContent(commandRevision: commandRevision)
        #if DEBUG
            let qaCommand = ScholiumQACommandContent(commandRevision: commandRevision)
        #endif
        CommandGroup(replacing: .newItem) {
            fileCreationCommand
        }
        CommandGroup(after: .newItem) {
            Divider()
            ScholiumCloseTabCommandContent(commandRevision: commandRevision)
            Divider()
            fileDocumentCommand
        }
        CommandGroup(after: .pasteboard) {
            pasteboardCommand
        }
        // Scholium owns Markdown formatting semantics. Replacing the system
        // rich-text group prevents NSText/HTML editing actions from competing
        // with the exact-source commands exposed below.
        CommandGroup(replacing: .textFormatting) {
            textFormattingCommand
        }
        CommandMenu("Insert") {
            insertCommand
        }
        CommandGroup(replacing: .sidebar) {
            viewCommand
        }
        CommandMenu("Research") {
            ScholiumResearchCommandContent(commandRevision: commandRevision)
        }
        CommandGroup(after: .windowArrangement) {
            ScholiumWindowCommandContent(commandRevision: commandRevision)
            Divider()
            attentionCommand
        }
        #if DEBUG
            if qaEditorFaultsAreEnabled || qaOperationProofsAreEnabled {
                CommandMenu("QA") {
                    qaCommand
                }
            }
        #endif
    }

    #if DEBUG
        private var qaEditorFaultsAreEnabled: Bool {
            Bundle.main.bundleIdentifier == "com.scholium.qa"
                && ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults")
        }

        private var qaOperationProofsAreEnabled: Bool {
            Bundle.main.bundleIdentifier == "com.scholium.qa"
                && ProcessInfo.processInfo.arguments.contains(
                    "--scholium-operation-proofs"
                )
        }
    #endif

}
