import AppKit
import ScholiumContracts
import SwiftUI

private struct ScholiumFileCreationCommandContent: View {
    let commandRevision: UInt64
    let storageReady: Bool
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var appState: WindowModel?

    var body: some View {
        Button("New Note") {
            appState?.libraryMutationController.requestUntitledNoteCreation(in: nil)
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
        Divider()
        Button("New Triptych…") {
            openWindow(
                id: "scholium-bootstrap",
                value: BootstrapWindowRoute(purpose: .newTriptych)
            )
        }
        .scholiumActivationPointer()
        .disabled(!storageReady)
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

    var body: some View {
        Button("Close Tab") {
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

private struct ScholiumFileDocumentCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
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
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
        Button("Paste as Markdown") {
            guard let payload = markdownPasteboardPayload() else { return }
            editorActions?.performWithArgument(.pasteMarkdown, payload)
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.pasteMarkdown)
        .disabled(editorActions?.isAvailable(.pasteMarkdown) != true)
        Divider()
        Menu("Find") {
            Button("Find…") { editorActions?.presentFind() }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.find)
                .disabled(editorActions == nil)
            Button("Find and Replace…") { editorActions?.presentReplace() }
                .scholiumActivationPointer()
                .disabled(editorActions?.allowsReplace != true)
            Divider()
            Button("Find Next") { editorActions?.findNext() }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.findNext)
                .disabled(editorActions == nil)
            Button("Find Previous") { editorActions?.findPrevious() }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.findPrevious)
                .disabled(editorActions == nil)
            Button("Use Selection for Find") { editorActions?.useSelectionForFind() }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.useSelectionForFind)
                .disabled(editorActions == nil)
        }
        .scholiumActivationPointer()
        .disabled(appState?.currentNote == nil)
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
    @FocusedValue(\.scholiumEditorActions) private var editorActions

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
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    let commandRevision: UInt64
    @FocusedValue(\.scholiumEditorActions) private var editorActions

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
        Button("Find Writing References…") {
            guard let appState else { return }
            appState.researchController.selectInspectorMode(.related)
            workspaceWindowActions?.setResearchInspectorVisible(true)
            appState.findRelatedMaterials(paragraph: true)
        }
        .scholiumKeyboardShortcut(.findWritingReferences)
        .disabled(appState?.canFindWritingReferences != true)
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
            Button("Orientation") { editorActions?.perform(.calloutOrient) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutOrient) != true)
            Button("Source") { editorActions?.perform(.calloutCite) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutCite) != true)
            Button("Connections") { editorActions?.perform(.calloutConnect) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutConnect) != true)
            Button("Statement") { editorActions?.perform(.calloutState) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutState) != true)
            Button("Illustration") { editorActions?.perform(.calloutIllustrate) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutIllustrate) != true)
            Button("Quotation") { editorActions?.perform(.calloutQuote) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutQuote) != true)
            Button("Caution") { editorActions?.perform(.calloutFlag) }
                .scholiumActivationPointer()
                .disabled(editorActions?.isAvailable(.calloutFlag) != true)
        }
        .scholiumActivationPointer()
    }
}

private struct ScholiumViewCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    @FocusedValue(\.scholiumEditorActions) private var editorActions

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
        .disabled(workspaceWindowActions == nil || appState?.shellState.isFocusLayoutLockedByFullScreen == true)
        Button("Library") {
            workspaceWindowActions?.activateSidebar(.triptych)
        }
        .disabled(workspaceWindowActions == nil || appState?.shellState.isFocusLayoutLockedByFullScreen == true)
        Button("Chat") { workspaceWindowActions?.activateSidebar(.chat) }
            .disabled(appState?.workspaceAssignment == nil || appState?.shellState.isFocusLayoutLockedByFullScreen == true)
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
                appState?.presentedDocumentMode == .read ? "Edit" : "Review"
            )
        ) {
            guard let destination = reviewEditDestination else { return }
            appState?.requestDocumentMode(destination)
        }
        .scholiumActivationPointer()
        .scholiumKeyboardShortcut(.toggleReviewEdit)
        .disabled(reviewEditDestination == nil || editorActions?.isComposing == true)
        Menu("Document Mode") {
            Button("Review") { appState?.requestDocumentMode(.read) }
                .scholiumActivationPointer()
            Button("Edit") { appState?.requestDocumentMode(.livePreview) }
                .scholiumActivationPointer()
                .disabled(appState?.canEditCurrentNote != true)
            if appState?.isDetachedDocumentWindow != true {
                Button("Source") { appState?.requestDocumentMode(.source) }
                    .scholiumActivationPointer()
                    .scholiumKeyboardShortcut(.showSource)
                    .disabled(appState?.canEditCurrentNote != true)
            }
        }
        .scholiumActivationPointer()
        .disabled(appState?.currentNote == nil || editorActions?.isComposing == true)
        Divider()
        Menu("Document Text Size") {
            Button("Increase Text Size") {
                appState?.adjustDocumentTextScale(by: ScholiumMetrics.Document.textScaleStep)
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.increaseTextSize)
            .disabled(
                appState?.currentNote == nil
                    || appState?.documentTextScale == ScholiumMetrics.Document.maximumTextScale
            )
            Button("Decrease Text Size") {
                appState?.adjustDocumentTextScale(by: -ScholiumMetrics.Document.textScaleStep)
            }
            .scholiumActivationPointer()
            .scholiumKeyboardShortcut(.decreaseTextSize)
            .disabled(
                appState?.currentNote == nil
                    || appState?.documentTextScale == ScholiumMetrics.Document.minimumTextScale
            )
            Button("Actual Size (100%)") { appState?.resetDocumentTextScale() }
                .scholiumActivationPointer()
                .scholiumKeyboardShortcut(.actualTextSize)
                .disabled(
                    appState?.currentNote == nil
                        || appState?.documentTextScale == ScholiumMetrics.Document.defaultTextScale
                )
            Divider()
            Button("150%") { appState?.setDocumentTextScale(1.5) }
                .scholiumActivationPointer()
                .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.5)
            Button("200%") {
                appState?.setDocumentTextScale(ScholiumMetrics.Document.maximumTextScale)
            }
            .scholiumActivationPointer()
            .disabled(
                appState?.currentNote == nil
                    || appState?.documentTextScale == ScholiumMetrics.Document.maximumTextScale
            )
        }
        .scholiumActivationPointer()
        .disabled(appState?.currentNote == nil)
        Menu("Appearance") {
            Button("Use System Appearance") { appState?.colorScheme = .system }
                .scholiumActivationPointer()
            Button("Light") { appState?.colorScheme = .light }
                .scholiumActivationPointer()
            Button("Dark") { appState?.colorScheme = .dark }
                .scholiumActivationPointer()
        }
        .scholiumActivationPointer()
    }

    private var reviewEditDestination: NotePresentationMode? {
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
        .disabled(appState?.currentNote == nil)
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
        .disabled(appState?.currentNote == nil)
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
        Button(workspaceWindowActions?.settlementMenuTitle() ?? ScholiumL10n.string("Settle")) {
            workspaceWindowActions?.showSettlement()
        }
        .disabled(workspaceWindowActions?.settlementMenuTitle() == nil)
        Divider()
        Button("Agent Changes…") {
            appState?.presentationRouter.present(.agentChanges(scope: .current))
        }
        .disabled(appState?.windowWorkspaceController.activeCapabilities == nil)
    }
}

private struct ScholiumWindowCommandContent: View {
    let commandRevision: UInt64
    @FocusedObject private var appState: WindowModel?

    var body: some View {
        Menu("Document Tabs") {
            ForEach(appState?.documentTabController.tabs ?? []) { tab in
                Button(tab.title) { appState?.selectDocumentTab(withID: tab.id) }
            }
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
        @FocusedObject private var appState: WindowModel?
        @FocusedValue(\.scholiumEditorActions) private var editorActions

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
    @FocusedValue(\.scholiumApplicationBootstrapStatus)
    private var applicationBootstrapStatus
    @FocusedObject private var commandObservation: WindowCommandObservation?

    var body: some Commands {
        let commandRevision = commandObservation?.revision ?? 0
        let storageReady = applicationBootstrapStatus?.isReady == true
        let fileCreationCommand = ScholiumFileCreationCommandContent(
            commandRevision: commandRevision,
            storageReady: storageReady
        )
        let fileDocumentCommand = ScholiumFileDocumentCommandContent(commandRevision: commandRevision)
        let pasteboardCommand = ScholiumPasteboardCommandContent(commandRevision: commandRevision)
        let textFormattingCommand = ScholiumTextFormattingCommandContent(commandRevision: commandRevision)
        let insertCommand = ScholiumInsertCommandContent(commandRevision: commandRevision)
        let viewCommand = ScholiumViewCommandContent(commandRevision: commandRevision)
        let attentionCommand = ScholiumAttentionCommandContent(commandRevision: commandRevision)
        #if DEBUG
            let qaCommand = ScholiumQACommandContent()
        #endif
        CommandGroup(replacing: .newItem) {
            fileCreationCommand
        }
        CommandGroup(after: .newItem) {
            ScholiumCloseTabCommandContent(commandRevision: commandRevision)
        }
        CommandGroup(after: .saveItem) {
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
