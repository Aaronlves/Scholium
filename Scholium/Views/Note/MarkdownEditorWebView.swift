import ScholiumContracts
import AppKit
import SwiftUI
import WebKit

private final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?
    weak var editorSession: MarkdownEditorSession?
    var onRequestComment: (() -> Void)?
    private var rightMouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeRightMouseMonitor()
            return
        }
        installRightMouseMonitorIfNeeded()
        guard let action = onFirstWindowAttachment else { return }
        onFirstWindowAttachment = nil
        action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        return prepareEditorContextMenu(
            menu,
            previewPoint: convert(event.locationInWindow, from: nil)
        )
    }

    private func installRightMouseMonitorIfNeeded() {
        guard rightMouseMonitor == nil else { return }
        rightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) {
            [weak self] event in
            self?.handleRightMouseDown(event) ?? event
        }
    }

    private func removeRightMouseMonitor() {
        guard let rightMouseMonitor else { return }
        NSEvent.removeMonitor(rightMouseMonitor)
        self.rightMouseMonitor = nil
    }

    private func handleRightMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        // WKWebView dispatches pointer events to a private descendant view, so
        // overriding the outer view's menu(for:) is not enough. Ask the actual
        // hit view for WebKit's standard menu, append Scholium's domain
        // commands, then consume this one event to avoid a duplicate menu.
        let targetView = hitTest(point) ?? self
        let standardMenu = targetView === self
            ? (super.menu(for: event) ?? NSMenu())
            : (targetView.menu(for: event) ?? NSMenu())
        let menu = prepareEditorContextMenu(standardMenu, previewPoint: point)
        NSMenu.popUpContextMenu(menu, with: event, for: targetView)
        return nil
    }

    private func prepareEditorContextMenu(_ menu: NSMenu, previewPoint: NSPoint? = nil) -> NSMenu {
        menu.identifier = NSUserInterfaceItemIdentifier("scholium.editor.contextMenu")
        for item in menu.items where item.identifier?.rawValue.hasPrefix("scholium.editor.") == true {
            menu.removeItem(item)
        }
        guard let editorSession else { return menu }
        let available = Set(editorSession.context?.availableCommands ?? [])
        var addedAction = false
        for (title, command) in [
            (ScholiumL10n.string("Bold"), MarkdownEditorCommand.bold),
            (ScholiumL10n.string("Emphasis"), .emphasis),
            (ScholiumL10n.string("Link"), .standardLink),
            (ScholiumL10n.string("Toggle Task"), .toggleTask),
        ] where available.contains(command) {
            if !addedAction { menu.addItem(.separator()) }
            menu.addItem(editorMenuItem(title, command: command))
            addedAction = true
        }

        let tableCommands: [(String, MarkdownEditorCommand)] = [
            (ScholiumL10n.string("Insert Row Before"), .tableInsertRowBefore),
            (ScholiumL10n.string("Insert Row After"), .tableInsertRowAfter),
            (ScholiumL10n.string("Delete Row"), .tableDeleteRow),
            (ScholiumL10n.string("Insert Column Before"), .tableInsertColumnBefore),
            (ScholiumL10n.string("Insert Column After"), .tableInsertColumnAfter),
            (ScholiumL10n.string("Delete Column"), .tableDeleteColumn),
            (ScholiumL10n.string("Align Left"), .tableAlignLeft),
            (ScholiumL10n.string("Align Center"), .tableAlignCenter),
            (ScholiumL10n.string("Align Right"), .tableAlignRight),
        ].filter { available.contains($0.1) }
        if !tableCommands.isEmpty {
            if !addedAction { menu.addItem(.separator()) }
            let submenu = NSMenu(title: ScholiumL10n.string("Table"))
            tableCommands.forEach { submenu.addItem(editorMenuItem($0.0, command: $0.1)) }
            let item = NSMenuItem(title: ScholiumL10n.string("Table"), action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.table")
            item.submenu = submenu
            menu.addItem(item)
            addedAction = true
        }
        if editorSession.canAttemptPreview {
            if !addedAction { menu.addItem(.separator()) }
            let item = NSMenuItem(
                title: ScholiumL10n.string("Preview"),
                action: #selector(showPreview(_:)),
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.preview")
            item.target = self
            if let previewPoint {
                item.representedObject = NSValue(point: previewPoint)
            }
            menu.addItem(item)
            addedAction = true
        }
        if onRequestComment != nil,
           editorSession.context?.composing != true,
           editorSession.context?.selections.contains(where: \.isNonempty) == true {
            if !addedAction { menu.addItem(.separator()) }
            let item = NSMenuItem(title: ScholiumL10n.string("Add Comment…"), action: #selector(requestComment(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.comment")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private func editorMenuItem(_ title: String, command: MarkdownEditorCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performEditorCommand(_:)), keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(command.rawValue)")
        item.representedObject = command.rawValue
        item.target = self
        return item
    }

    @objc private func performEditorCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = MarkdownEditorCommand(rawValue: rawValue),
              let editorSession else { return }
        Task { @MainActor in
            do {
                try await editorSession.perform(command)
            } catch {
                editorSession.reportError(error.localizedDescription)
            }
        }
    }

    @objc private func requestComment(_ sender: NSMenuItem) {
        onRequestComment?()
    }

    @objc private func showPreview(_ sender: NSMenuItem) {
        if let point = (sender.representedObject as? NSValue)?.pointValue {
            editorSession?.showPreview(
                at: CGPoint(
                    x: point.x,
                    y: isFlipped ? point.y : bounds.height - point.y
                )
            )
        } else {
            editorSession?.showPreview()
        }
    }
}

enum NotePresentationMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case read
    case livePreview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: ScholiumL10n.string("Read")
        case .livePreview: ScholiumL10n.string("Live Preview")
        case .source: ScholiumL10n.string("Source")
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .livePreview: "text.page.badge.magnifyingglass"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct EditorLinkCompletion: Codable, Hashable, Sendable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let isAmbiguous: Bool
}

struct MarkdownEditorCommentAnnotation: Codable, Hashable, Sendable {
    let id: UUID
    let from: Int
    let to: Int
    let comment: String
    let resolved: Bool
}

private struct EditorBridgeChange: Codable {
    let from: Int
    let to: Int
    let insert: String
}

private struct EditorBridgeMessage: Codable {
    let type: String
    let protocolVersion: Int?
    let sessionID: String?
    let documentID: String?
    let startingFingerprint: String?
    let documentVersion: Int?
    let baseGeneration: Int?
    let resultingGeneration: Int?
    let changes: [EditorBridgeChange]?
    let dirty: Bool?
    let line: Int?
    let column: Int?
    let lineCount: Int?
    let selections: [MarkdownEditorSelectionRange]?
    let message: String?
    let editorReady: Bool?
    let scrollFraction: Double?
    let scrollAnchor: MarkdownEditorWireScrollAnchor?
    let commentID: String?
    let target: String?
    let context: MarkdownEditorContext?
}

@MainActor
protocol MarkdownEditorBridgeDispatching: AnyObject {
    func dispatch(
        requestJSON: String,
        in webView: WKWebView
    ) async throws -> Any?
}

@MainActor
final class WKWebViewMarkdownEditorBridgeDispatcher: MarkdownEditorBridgeDispatching {
    func dispatch(
        requestJSON: String,
        in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            "return await window.scholiumEditor.dispatch(JSON.parse(requestJSON))",
            arguments: ["requestJSON": requestJSON],
            in: nil,
            contentWorld: .page
        )
    }
}

@MainActor
final class MarkdownEditorSession: NSObject, ObservableObject {
    private struct BridgeRequestContext {
        let requestEpoch: UInt64
        let sessionID: UUID
        let documentID: String
        let startingFingerprint: String
        let generation: Int
        let webView: WKWebView
    }

    private struct RecoveryCaptureKey: Equatable {
        let requestEpoch: UInt64
        let generation: Int
    }

    enum SessionError: LocalizedError {
        case unavailable
        case invalidResult
        case selectionTooLong
        case staleRequest
        case bridgeRejected(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor returned an invalid document."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            case .staleRequest: "The Markdown editor request belonged to a replaced document or session."
            case .bridgeRejected(let message): message
            }
        }
    }

    @Published private(set) var isReady = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isDirty = false
    private(set) var line = 1
    private(set) var column = 1
    private(set) var lineCount = 1
    @Published private(set) var errorMessage: String?
    @Published private(set) var interactionAvailability: EditorInteractionAvailability?
    private(set) var context: MarkdownEditorContext?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""

    /// Opaque identity for the CodeMirror document owned by this retained
    /// session. A vault-relative path is a mutable projection and must not
    /// force a new EditorState when the same stable note is renamed.
    var bridgeDocumentID: String { sessionID.uuidString }
    private(set) var startingFingerprint = ""
    private(set) var generation = 0

    private var webView: WKWebView?
    private var pendingSource: String?
    private var pendingDocumentID = ""
    private var pendingMode: NotePresentationMode = .livePreview
    private var pendingPresentationCSS = ""
    private var pendingUserCSS = ""
    private var pendingLine: Int?
    private var pendingLinkCompletions: [EditorLinkCompletion] = []
    private var pendingLinkPreviews: [MarkdownEditorLinkPreview] = []
    private var pendingResearcherComments: [MarkdownEditorCommentAnnotation] = []
    private var pendingScrollFraction: Double?
    private var pendingScrollAnchor: EditorScrollAnchor?
    private var reconstructionScrollAnchor: EditorScrollAnchor?
    private var startupTask: Task<Void, Never>?
    private var recoveryCaptureTask: Task<Void, Never>?
    private var scheduledRecoveryCaptureKey: RecoveryCaptureKey?
    private var recoveryCaptureToken: UInt64 = 0
    private var requestBarrier: Task<Void, Never>?
    private var inFlightRequestTasks: [UUID: Task<MarkdownEditorCommandResult, Error>] = [:]
    private var requestEpoch: UInt64 = 0
    private let bridgeDispatcher: any MarkdownEditorBridgeDispatching
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private var committedTextSynchronizer: ((String, String) -> Void)?
    private var sourceChangeHandler: ((String) -> Void)?
    private var checkedSource = ""
    private var checkedEditorUTF16Length = 0
    private var recoverySnapshot: MarkdownEditorRecoverySnapshot?
    private var lastKnownSelectionSnapshot: MarkdownEditorSelectionSnapshot?
    #if DEBUG
    private static let qaTerminationNotification = Notification.Name(
        "com.scholium.qa.simulate-editor-process-termination"
    )
    private var qaTerminationObserverInstalled = false
    #endif
    var hasAttachedWebView: Bool { webView != nil }
    var canAttemptPreview: Bool { pendingMode == .livePreview }
    var canShowPreviewAtSelection: Bool {
        guard pendingMode == .livePreview,
              let selectionSnapshot = lastKnownSelectionSnapshot,
              selectionSnapshot.isValid(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                editorUTF16Length: checkedEditorUTF16Length
              ),
              let head = selectionSnapshot.ranges.first?.head else { return false }
        if pendingLinkPreviews.contains(where: { head >= $0.from && head < $0.to }) {
            return true
        }
        let normalized = checkedSource.replacingOccurrences(of: "\r\n", with: "\n") as NSString
        guard head >= 0, head <= normalized.length,
              let expression = try? NSRegularExpression(pattern: #"\[\^([^\]\n]{1,240})\]"#) else {
            return false
        }
        return expression.matches(
            in: normalized as String,
            range: NSRange(location: 0, length: normalized.length)
        ).contains { match in
            guard NSLocationInRange(head, NSRange(location: match.range.location, length: match.range.length + 1)) else {
                return false
            }
            let precedingNewline = normalized.range(
                of: "\n",
                options: .backwards,
                range: NSRange(location: 0, length: match.range.location)
            )
            let lineStart = precedingNewline.location == NSNotFound
                ? 0
                : precedingNewline.location + precedingNewline.length
            let prefix = normalized.substring(with: NSRange(
                location: lineStart,
                length: match.range.location - lineStart
            ))
            let following = match.range.upperBound < normalized.length
                ? normalized.substring(with: NSRange(location: match.range.upperBound, length: 1))
                : ""
            return !prefix.allSatisfy(\.isWhitespace) || following != ":"
        }
    }

    override convenience init() {
        self.init(
            bridgeDispatcher: WKWebViewMarkdownEditorBridgeDispatcher(),
            lifecyclePolicy: ScholiumLifecyclePolicy()
        )
    }

    init(
        bridgeDispatcher: any MarkdownEditorBridgeDispatching,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy()
    ) {
        self.bridgeDispatcher = bridgeDispatcher
        self.lifecyclePolicy = lifecyclePolicy
        super.init()
    }

    #if DEBUG
    struct TestingPresentationSnapshot: Decodable, Sendable {
        let rootContentTopInset: String
        let rootTextScale: String
        let rootProseLineHeight: String
        let rootParagraphGap: String
        let rootHeadingLineHeight: String
        let rootInlineRegular: String
        let rootInlineSource: String
        let rootInlineNarrow: String
        let viewportWidth: Double
        let pageColor: String
        let pageBackgroundColor: String
        let documentFontFamily: String
        let documentFontSize: String
        let documentLineHeight: String
        let documentMaxWidth: String
        let documentPaddingTop: String
        let documentPaddingInlineStart: String
        let documentWidth: Double
        let documentLeft: Double
        let documentRight: Double
        let firstGlyphLeft: Double
        let pageHorizontalOverflow: Double
        let latinGlyphsPerLine: Int
        let cjkGlyphsPerLine: Int
        let headingFontFamily: String
        let headingFontSize: String
        let headingFontWeight: String
        let headingLineHeight: String
        let headingBlockBefore: Double
        let headingBlockAfter: Double
        let headingWidth: Double
        let headingTextDecorationLine: String
        let titleTextDecorationLine: String
        let titleBorderBottomWidth: String
        let titleWidth: Double
        let calloutAccent: String
        let calloutBorderColor: String
        let calloutFontSize: String
        let calloutLineHeight: String
        let calloutWidth: Double
        let calloutRoleColor: String
        let calloutRolePosition: String
        let calloutRoleWidth: Double
        let calloutRoleHeight: Double
        let calloutRoleFontFamily: String
        let calloutRoleFontSize: String
        let calloutRoleFontWeight: String
        let calloutRoleLineHeight: String
        let calloutRoleLetterSpacing: String
        let calloutRoleTextTransform: String
        let calloutTitleColor: String
        let calloutTitleFontFamily: String
        let calloutTitleFontSize: String
        let calloutTitleFontWeight: String
        let calloutTitleLineHeight: String
        let calloutTitleLetterSpacing: String
        let calloutTitleTextTransform: String
        let orientationTextAlign: String
        let tableOverflowX: String
        let tableWidth: Double
        let tableCellFontFamily: String
        let tableCellFontSize: String
        let tableCellLineHeight: String
        let tableCellPaddingBlockStart: String
        let tableCellPaddingInlineStart: String
        let tableCellBorderBottomWidth: String
        let tableCellBorderBottomColor: String
        let footnoteFontFamily: String
        let footnoteColor: String
        let footnoteFontSize: String
        let footnoteLineHeight: String
        let footnoteMarginBlockStart: String
        let footnoteListPaddingInlineStart: String
        let footnoteWidth: Double
        let mathOverflowX: String
        let mathColor: String
        let mathFontSize: String
        let mathLineHeight: String
        let mathMarginBlockStart: String
        let mathPaddingBlockStart: String
        let mathWidth: Double
    }

    struct TestingAccessibilitySnapshot: Decodable, Sendable {
        let contentEditableCount: Int
        let textboxCount: Int
        let label: String
        let multiline: String
        let hasValueText: Bool
        let spellcheck: String
        let isFocused: Bool
        let gutterCount: Int
        let lineNumberCount: Int
        let activeLineCount: Int
        let contentPaddingTop: String
        let contentPaddingInlineStart: String
        let scrollTop: Double
        let scrollExtent: Double
        let mathRuntimeVersion: Int
        let renderedMathCount: Int
        let mathErrorCount: Int
        let displayMathOverflowX: String
        let previewAnchorCount: Int
        let previewPopoverHidden: Bool
        let previewTitle: String
        let previewNestedListCount: Int
        let previewBlockquoteCount: Int
        let previewCodeBlockCount: Int
        let previewCalloutCount: Int
        let previewTableCount: Int
        let previewRenderedMathCount: Int
        let frontmatterLineCount: Int
        let frontmatterVisibleHeight: Double
        let unclosedFrontmatterNoticeCount: Int
        let semanticTableCount: Int
        let liveTableSourceLineCount: Int
        let tableHeaderCount: Int
        let tableBodyCellCount: Int
        let tableStrongCount: Int
        let tableFirstHeaderText: String
        let tableOverflowX: String
        let footnoteReferenceCount: Int
        let footnoteSectionCount: Int
        let footnoteItemCount: Int
        let footnoteStrongCount: Int
        let footnoteNestedListCount: Int
        let footnoteBlockquoteCount: Int
        let footnoteCodeBlockCount: Int
        let footnoteCalloutCount: Int
        let footnoteTableCount: Int
        let footnoteRenderedMathCount: Int
        let footnoteDefinitionSourceCount: Int
        let liveCalloutWidgetCount: Int
        let liveCalloutSourceLineCount: Int
        let exactWikilinkSourceCount: Int
        let incompleteWikilinkSourceCount: Int
        let exactCalloutSourceCount: Int
        let presentation: TestingPresentationSnapshot
    }

    @discardableResult
    func testingSimulateWebContentProcessTermination() -> Bool {
        guard let webView,
              let coordinator = webView.navigationDelegate as? MarkdownEditorWebView.Coordinator else {
            return false
        }
        coordinator.webViewWebContentProcessDidTerminate(webView)
        return true
    }

    func testingAccessibilitySnapshot() async throws -> TestingAccessibilitySnapshot {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const editable = document.querySelectorAll('[contenteditable="true"]');
            const textboxes = document.querySelectorAll('[role="textbox"]');
            const content = editable[0];
            const contentStyle = content ? getComputedStyle(content) : null;
            const rootStyle = getComputedStyle(document.documentElement);
            const px = value => Number.parseFloat(value || '0') || 0;
            const style = selector => {
                const element = document.querySelector(selector);
                return element ? getComputedStyle(element) : null;
            };
            const width = selector => document.querySelector(selector)?.getBoundingClientRect().width || 0;
            const bounds = selector => document.querySelector(selector)?.getBoundingClientRect() || {left: 0, right: 0};
            const firstGlyphLeft = selector => {
                const element = document.querySelector(selector);
                if (!element) return 0;
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    if (!node.textContent?.trim()) continue;
                    const offset = node.textContent.search(/\\S/);
                    const range = document.createRange();
                    range.setStart(node, Math.max(0, offset));
                    range.setEnd(node, Math.max(0, offset) + 1);
                    return range.getBoundingClientRect().left;
                }
                return 0;
            };
            const maximumGlyphsOnLine = marker => {
                const element = Array.from(document.querySelectorAll('.cm-line'))
                    .find(candidate => candidate.textContent?.includes(marker));
                if (!element) return 0;
                const counts = new Map();
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    let offset = 0;
                    for (const glyph of Array.from(node.textContent || '')) {
                        const nextOffset = offset + glyph.length;
                        if (!/[\\r\\n]/u.test(glyph)) {
                            const range = document.createRange();
                            range.setStart(node, offset);
                            range.setEnd(node, nextOffset);
                            const rect = range.getClientRects()[0];
                            if (rect) {
                                const line = Math.round(rect.top * 2) / 2;
                                counts.set(line, (counts.get(line) || 0) + 1);
                            }
                        }
                        offset = nextOffset;
                    }
                }
                return Math.max(0, ...counts.values());
            };
            const textStyle = selector => {
                const element = document.querySelector(selector);
                if (!element) return null;
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    if (node.textContent?.trim()) return getComputedStyle(node.parentElement || element);
                }
                return getComputedStyle(element);
            };
            const headingBlockStyle = style('.cm-live-h2');
            const headingStyle = textStyle('.cm-live-h2');
            const titleBlockStyle = style('.cm-live-document-title');
            const titleStyle = textStyle('.cm-live-document-title');
            const calloutStyle = style('.cm-live-callout-widget.scholium-callout-state');
            const calloutRoleStyle = style('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role');
            const calloutTitleStyle = style('.cm-live-callout-widget.scholium-callout-state .scholium-callout-title');
            const orientationStyle = style('.cm-live-callout-widget.scholium-callout-orient .scholium-callout-body');
            const tableStyle = style('.cm-live-table-widget');
            const tableCellStyle = style('.cm-live-table-widget th');
            const footnoteStyle = style('.cm-live-footnotes-widget');
            const footnoteListStyle = style('.cm-live-footnotes-widget > ol');
            const mathStyle = style('.cm-live-math.scholium-math-display');
            return {
                contentEditableCount: editable.length,
                textboxCount: textboxes.length,
                label: content?.getAttribute('aria-label') || '',
                multiline: content?.getAttribute('aria-multiline') || '',
                hasValueText: content?.hasAttribute('aria-valuetext') || false,
                spellcheck: content?.getAttribute('spellcheck') || '',
                isFocused: document.activeElement === content,
                gutterCount: document.querySelectorAll('.cm-gutters').length,
                lineNumberCount: document.querySelectorAll('.cm-lineNumbers .cm-gutterElement').length,
                activeLineCount: document.querySelectorAll('.cm-activeLine').length,
                contentPaddingTop: contentStyle?.paddingTop || '',
                contentPaddingInlineStart: contentStyle?.paddingInlineStart || '',
                scrollTop: document.querySelector('.cm-scroller')?.scrollTop || 0,
                scrollExtent: (() => {
                    const scroller = document.querySelector('.cm-scroller');
                    return scroller ? Math.max(0, scroller.scrollHeight - scroller.clientHeight) : 0;
                })(),
                mathRuntimeVersion: window.scholiumMath?.version || 0,
                renderedMathCount: document.querySelectorAll('.cm-live-math.scholium-math-rendered').length,
                mathErrorCount: document.querySelectorAll('.cm-live-math.scholium-math-error').length,
                displayMathOverflowX: (() => {
                    const display = document.querySelector('.cm-live-math.scholium-math-display');
                    return display ? getComputedStyle(display).overflowX : '';
                })(),
                previewAnchorCount: document.querySelectorAll('[data-link-preview-index], [data-footnote-preview-id]').length,
                previewPopoverHidden: document.getElementById('scholium-preview-popover')?.hidden !== false,
                previewTitle: document.querySelector('#scholium-preview-popover .scholium-preview-title')?.textContent || '',
                previewNestedListCount: document.querySelectorAll('#scholium-preview-popover ul ul').length,
                previewBlockquoteCount: document.querySelectorAll('#scholium-preview-popover blockquote').length,
                previewCodeBlockCount: document.querySelectorAll('#scholium-preview-popover pre code.language-swift').length,
                previewCalloutCount: document.querySelectorAll('#scholium-preview-popover .scholium-callout-state').length,
                previewTableCount: document.querySelectorAll('#scholium-preview-popover table.scholium-table').length,
                previewRenderedMathCount: document.querySelectorAll('#scholium-preview-popover .scholium-math-rendered').length,
                frontmatterLineCount: document.querySelectorAll('.cm-live-frontmatter').length,
                frontmatterVisibleHeight: Array.from(document.querySelectorAll('.cm-live-frontmatter'))
                    .reduce((height, line) => height + line.getBoundingClientRect().height, 0),
                unclosedFrontmatterNoticeCount: document.querySelectorAll('.cm-live-frontmatter-unavailable').length,
                semanticTableCount: document.querySelectorAll('.cm-live-table-widget .scholium-table').length,
                liveTableSourceLineCount: document.querySelectorAll('.cm-line.cm-live-table').length,
                tableHeaderCount: document.querySelectorAll('.cm-live-table-widget th[scope="col"]').length,
                tableBodyCellCount: document.querySelectorAll('.cm-live-table-widget tbody td').length,
                tableStrongCount: document.querySelectorAll('.cm-live-table-widget strong').length,
                tableFirstHeaderText: document.querySelector('.cm-live-table-widget th')?.textContent || '',
                tableOverflowX: (() => {
                    const scroller = document.querySelector('.cm-live-table-widget');
                    return scroller ? getComputedStyle(scroller).overflowX : '';
                })(),
                footnoteReferenceCount: document.querySelectorAll('.cm-live-footnote-reference-widget .footnote-reference').length,
                footnoteSectionCount: document.querySelectorAll('.cm-live-footnotes-widget').length,
                footnoteItemCount: document.querySelectorAll('.cm-live-footnotes-widget > ol > li').length,
                footnoteStrongCount: document.querySelectorAll('.cm-live-footnotes-widget strong').length,
                footnoteNestedListCount: document.querySelectorAll('.cm-live-footnotes-widget ul ul').length,
                footnoteBlockquoteCount: document.querySelectorAll('.cm-live-footnotes-widget blockquote').length,
                footnoteCodeBlockCount: document.querySelectorAll('.cm-live-footnotes-widget pre code.language-swift').length,
                footnoteCalloutCount: document.querySelectorAll('.cm-live-footnotes-widget .scholium-callout-state').length,
                footnoteTableCount: document.querySelectorAll('.cm-live-footnotes-widget table.scholium-table').length,
                footnoteRenderedMathCount: document.querySelectorAll('.cm-live-footnotes-widget .scholium-math-rendered').length,
                footnoteDefinitionSourceCount: document.querySelectorAll('.cm-live-footnote-definition-source').length,
                liveCalloutWidgetCount: document.querySelectorAll('.cm-live-callout-widget.scholium-callout').length,
                liveCalloutSourceLineCount: document.querySelectorAll('.cm-line.cm-live-callout').length,
                exactWikilinkSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[[') && line.textContent?.includes(']]')).length,
                incompleteWikilinkSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[[') !== line.textContent?.includes(']]')).length,
                exactCalloutSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[!')).length,
                presentation: {
                    rootContentTopInset: rootStyle.getPropertyValue('--scholium-document-content-top-inset').trim(),
                    rootTextScale: rootStyle.getPropertyValue('--scholium-document-text-scale').trim(),
                    rootProseLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-prose-line-height').trim(),
                    rootParagraphGap: rootStyle.getPropertyValue('--scholium-rhythm-paragraph-gap').trim(),
                    rootHeadingLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-heading-line-height').trim(),
                    rootInlineRegular: rootStyle.getPropertyValue('--scholium-rhythm-inline-regular').trim(),
                    rootInlineSource: rootStyle.getPropertyValue('--scholium-rhythm-inline-source').trim(),
                    rootInlineNarrow: rootStyle.getPropertyValue('--scholium-rhythm-inline-narrow').trim(),
                    viewportWidth: document.documentElement.clientWidth,
                    pageColor: style('.cm-scroller')?.color || '',
                    pageBackgroundColor: style('.cm-editor')?.backgroundColor || '',
                    documentFontFamily: style('.cm-scroller')?.fontFamily || '',
                    documentFontSize: style('.cm-scroller')?.fontSize || '',
                    documentLineHeight: style('.cm-scroller')?.lineHeight || '',
                    documentMaxWidth: contentStyle?.maxWidth || '',
                    documentPaddingTop: contentStyle?.paddingTop || '',
                    documentPaddingInlineStart: contentStyle?.paddingInlineStart || '',
                    documentWidth: width('.cm-content'),
                    documentLeft: bounds('.cm-content').left,
                    documentRight: bounds('.cm-content').right,
                    firstGlyphLeft: firstGlyphLeft('.cm-live-h2'),
                    pageHorizontalOverflow: Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth),
                    latinGlyphsPerLine: maximumGlyphsOnLine('LATIN_GRID_PROBE'),
                    cjkGlyphsPerLine: maximumGlyphsOnLine('CJK_GRID_PROBE'),
                    headingFontFamily: headingStyle?.fontFamily || '',
                    headingFontSize: headingStyle?.fontSize || '',
                    headingFontWeight: headingStyle?.fontWeight || '',
                    headingLineHeight: headingStyle?.lineHeight || '',
                    headingBlockBefore: px(headingBlockStyle?.marginTop) + px(headingBlockStyle?.paddingTop),
                    headingBlockAfter: px(headingBlockStyle?.marginBottom) + px(headingBlockStyle?.paddingBottom),
                    headingWidth: width('.cm-live-h2'),
                    headingTextDecorationLine: headingStyle?.textDecorationLine || '',
                    titleTextDecorationLine: titleStyle?.textDecorationLine || '',
                    titleBorderBottomWidth: titleBlockStyle?.borderBottomWidth || '',
                    titleWidth: width('.cm-live-document-title'),
                    calloutAccent: calloutStyle?.getPropertyValue('--callout-accent').trim() || '',
                    calloutBorderColor: calloutStyle?.borderInlineStartColor || '',
                    calloutFontSize: calloutStyle?.fontSize || '',
                    calloutLineHeight: calloutStyle?.lineHeight || '',
                    calloutWidth: width('.cm-live-callout-widget.scholium-callout-state'),
                    calloutRoleColor: calloutRoleStyle?.color || '',
                    calloutRolePosition: calloutRoleStyle?.position || '',
                    calloutRoleWidth: width('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role'),
                    calloutRoleHeight: document.querySelector('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role')?.getBoundingClientRect().height || 0,
                    calloutRoleFontFamily: calloutRoleStyle?.fontFamily || '',
                    calloutRoleFontSize: calloutRoleStyle?.fontSize || '',
                    calloutRoleFontWeight: calloutRoleStyle?.fontWeight || '',
                    calloutRoleLineHeight: calloutRoleStyle?.lineHeight || '',
                    calloutRoleLetterSpacing: calloutRoleStyle?.letterSpacing || '',
                    calloutRoleTextTransform: calloutRoleStyle?.textTransform || '',
                    calloutTitleColor: calloutTitleStyle?.color || '',
                    calloutTitleFontFamily: calloutTitleStyle?.fontFamily || '',
                    calloutTitleFontSize: calloutTitleStyle?.fontSize || '',
                    calloutTitleFontWeight: calloutTitleStyle?.fontWeight || '',
                    calloutTitleLineHeight: calloutTitleStyle?.lineHeight || '',
                    calloutTitleLetterSpacing: calloutTitleStyle?.letterSpacing || '',
                    calloutTitleTextTransform: calloutTitleStyle?.textTransform || '',
                    orientationTextAlign: orientationStyle?.textAlign || '',
                    tableOverflowX: tableStyle?.overflowX || '',
                    tableWidth: width('.cm-live-table-widget'),
                    tableCellFontFamily: tableCellStyle?.fontFamily || '',
                    tableCellFontSize: tableCellStyle?.fontSize || '',
                    tableCellLineHeight: tableCellStyle?.lineHeight || '',
                    tableCellPaddingBlockStart: tableCellStyle?.paddingBlockStart || '',
                    tableCellPaddingInlineStart: tableCellStyle?.paddingInlineStart || '',
                    tableCellBorderBottomWidth: tableCellStyle?.borderBottomWidth || '',
                    tableCellBorderBottomColor: tableCellStyle?.borderBottomColor || '',
                    footnoteFontFamily: footnoteStyle?.fontFamily || '',
                    footnoteColor: footnoteStyle?.color || '',
                    footnoteFontSize: footnoteStyle?.fontSize || '',
                    footnoteLineHeight: footnoteStyle?.lineHeight || '',
                    footnoteMarginBlockStart: footnoteStyle?.marginBlockStart || '',
                    footnoteListPaddingInlineStart: footnoteListStyle?.paddingInlineStart || '',
                    footnoteWidth: width('.cm-live-footnotes-widget'),
                    mathOverflowX: mathStyle?.overflowX || '',
                    mathColor: mathStyle?.color || '',
                    mathFontSize: mathStyle?.fontSize || '',
                    mathLineHeight: mathStyle?.lineHeight || '',
                    mathMarginBlockStart: mathStyle?.marginBlockStart || '',
                    mathPaddingBlockStart: mathStyle?.paddingBlockStart || '',
                    mathWidth: width('.cm-live-math.scholium-math-display')
                }
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any) else {
            throw SessionError.invalidResult
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
            throw SessionError.invalidResult
        }
        return try JSONDecoder().decode(TestingAccessibilitySnapshot.self, from: data)
    }

    func testingRevealFirstFootnoteDefinition() async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const item = document.querySelector('.cm-live-footnotes-widget li');
            if (!item) return false;
            return !item.dispatchEvent(new MouseEvent('mousedown', {
                bubbles: true,
                cancelable: true
            }));
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingClickFirstCalloutText(_ requestedText: String) async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const root = document.querySelector('.cm-live-callout-widget.scholium-callout');
            if (!root) return false;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
                const index = node.textContent?.indexOf(requestedText) ?? -1;
                if (index < 0) continue;
                const range = document.createRange();
                range.setStart(node, index);
                range.setEnd(node, Math.min(node.length, index + Math.max(1, requestedText.length)));
                const rect = range.getBoundingClientRect();
                (node.parentElement || root).dispatchEvent(new MouseEvent('mousedown', {
                    bubbles: true,
                    cancelable: true,
                    clientX: rect.left + Math.min(8, rect.width / 2),
                    clientY: (rect.top + rect.bottom) / 2
                }));
                window.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
                return true;
            }
            return false;
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingPressArrow(_ key: String, shiftKey: Bool = false) async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.cm-content');
            if (!content) return false;
            const event = new KeyboardEvent('keydown', {
                key,
                shiftKey,
                bubbles: true,
                cancelable: true
            });
            content.dispatchEvent(event);
            return event.defaultPrevented;
            """,
            arguments: ["key": key, "shiftKey": shiftKey],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingPreviewFirstFootnote() async throws {
        guard let webView else { throw SessionError.unavailable }
        let result = try await webView.callAsyncJavaScript(
            """
            const anchor = document.querySelector('.cm-live-footnote-reference-widget [data-footnote-preview-id]');
            if (!anchor) return false;
            anchor.dispatchEvent(new PointerEvent('pointermove', {
                bubbles: true,
                cancelable: true,
                metaKey: true
            }));
            await new Promise(resolve => setTimeout(resolve, 350));
            return document.getElementById('scholium-preview-popover')?.hidden === false;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard result as? Bool == true else { throw SessionError.invalidResult }
    }

    func testingApplyScrollAnchor(_ anchor: EditorScrollAnchor) async throws {
        guard isReady, isLoaded, let webView,
              let wireAnchor = Self.wireAnchor(from: anchor, in: checkedSource) else {
            throw SessionError.invalidResult
        }
        pendingScrollAnchor = anchor
        pendingScrollFraction = anchor.fallbackFraction
        _ = try await send(.setScrollAnchor(wireAnchor), in: webView)
    }

    func testingApplyScrollFraction(_ fraction: Double) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let normalized = min(1, max(0, fraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = nil
        _ = try await send(.setScrollFraction(normalized), in: webView)
    }

    var testingRetainedScrollFraction: Double? { pendingScrollFraction }
    var testingRetainedScrollAnchor: EditorScrollAnchor? { pendingScrollAnchor }

    #endif

    fileprivate func attach(_ webView: WKWebView) {
        invalidateRequestQueue()
        self.webView = webView
        sessionID = UUID()
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.errorMessage, to: nil)
        installQATerminationObserverIfEnabled()
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.reportError(String(localized: "Live Preview did not finish starting.", table: "Localizable", bundle: .module))
        }
    }

    fileprivate func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        invalidateRequestQueue()
        startupTask?.cancel()
        cancelScheduledRecoveryCapture()
        self.webView = nil
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
        removeQATerminationObserver()
    }

    fileprivate func editorBecameReady() {
        startupTask?.cancel()
        updatePublished(\.isReady, to: true)
        flushPendingState()
    }

    /// Applies the rAF-coalesced v4 interaction envelope. Exact cursor
    /// coordinates stay readable for commands and recovery, but they are not
    /// Observable state. Only a semantic availability change invalidates UI.
    func updateInteraction(
        selections: [MarkdownEditorSelectionRange],
        line: Int,
        column: Int,
        lineCount: Int,
        documentVersion: Int,
        context semanticContext: MarkdownEditorContext?
    ) {
        guard documentVersion == generation,
              markdownEditorSelectionRangesAreValid(
                selections,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              semanticContext?.selections == nil || semanticContext?.selections == selections else { return }
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: documentVersion,
            ranges: selections
        )
        self.line = max(1, line)
        self.column = max(1, column)
        self.lineCount = max(1, lineCount)

        if let semanticContext {
            let availability = EditorInteractionAvailability(context: semanticContext)
            context = availability.context(selections: selections)
            updatePublished(\.interactionAvailability, to: availability)
        } else if let interactionAvailability {
            context = interactionAvailability.context(selections: selections)
        }
    }

    fileprivate func reportError(_ message: String) {
        startupTask?.cancel()
        updatePublished(\.errorMessage, to: message)
        updatePublished(\.isLoaded, to: false)
    }

    func loadDocument(
        _ source: String,
        documentID: String,
        mode: NotePresentationMode,
        preservingRecovery: Bool = false
    ) {
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        let retainedStartingFingerprint = preservingRecovery ? startingFingerprint : nil
        if !preservingRecovery {
            recoverySnapshot = nil
            lastKnownSelectionSnapshot = nil
            reconstructionScrollAnchor = nil
            context = nil
            updatePublished(\.interactionAvailability, to: nil)
        }
        pendingSource = source
        pendingDocumentID = documentID
        self.documentID = documentID
        startingFingerprint = retainedStartingFingerprint
            ?? DocumentFingerprint(content: source).sha256
        checkedSource = source
        checkedEditorUTF16Length = Self.normalizedEditorUTF16Length(of: source)
        generation = 0
        pendingMode = mode
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.isDirty, to: false)
        updatePublished(\.errorMessage, to: nil)
        flushPendingState()
    }

    func setMode(_ mode: NotePresentationMode) {
        guard mode != .read else { return }
        pendingMode = mode
        guard isReady, isLoaded, let webView else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await send(.setMode(mode), in: webView)
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: documentID,
                    mode: mode
                )
            } catch {
                let message = "The document mode change was not applied because the editor changed during text composition."
                updatePublished(\.errorMessage, to: message)
                _ = try? await send(.announceStatus(message), in: webView)
            }
        }
    }

    func setUserCSS(_ css: String) {
        pendingUserCSS = css
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.setUserCSS(css), in: webView)
        }
    }

    func setPresentationCSS(_ css: String) {
        pendingPresentationCSS = css
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.setPresentationCSS(css), in: webView)
        }
    }

    func goToLine(_ line: Int) {
        pendingLine = max(1, line)
        flushPendingLine()
    }

    func setScrollFraction(_ fraction: Double) {
        let normalized = min(1, max(0, fraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = nil
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setScrollFraction(normalized), in: webView)
        }
    }

    func setScrollPosition(anchor: EditorScrollAnchor?, fallbackFraction: Double) {
        let normalized = min(1, max(0, fallbackFraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = anchor
        guard isReady, isLoaded, let webView else { return }
        Task {
            if let anchor,
               let wireAnchor = Self.wireAnchor(from: anchor, in: checkedSource) {
                _ = try? await send(.setScrollAnchor(wireAnchor), in: webView)
            } else {
                _ = try? await send(.setScrollFraction(normalized), in: webView)
            }
        }
    }

    fileprivate func recordScrollFraction(_ fraction: Double) {
        pendingScrollFraction = min(1, max(0, fraction))
    }


    fileprivate func recordScrollPosition(
        _ wireAnchor: MarkdownEditorWireScrollAnchor?,
        fallbackFraction: Double
    ) -> EditorScrollAnchor? {
        let fraction = min(1, max(0, fallbackFraction))
        pendingScrollFraction = fraction
        guard let wireAnchor,
              let sourceOffset = Self.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.sourceUTF16Offset,
                in: checkedSource
              ),
              let lowerBound = Self.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.blockUTF16LowerBound,
                in: checkedSource
              ),
              let upperBound = Self.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.blockUTF16UpperBound,
                in: checkedSource
              ) else {
            pendingScrollAnchor = nil
            return nil
        }
        let anchor = EditorScrollAnchor(
            sourceFingerprint: DocumentFingerprint(content: checkedSource).sha256,
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: wireAnchor.relativeBlockPosition,
            fallbackFraction: fraction
        )
        guard anchor.isValid(forUTF16Length: checkedSource.utf16.count) else {
            pendingScrollAnchor = nil
            return nil
        }
        pendingScrollAnchor = anchor
        return anchor
    }

    fileprivate func retainedScrollFraction(fallback: Double) -> Double {
        pendingScrollFraction ?? min(1, max(0, fallback))
    }

    fileprivate var retainedScrollAnchor: EditorScrollAnchor? {
        reconstructionScrollAnchor ?? pendingScrollAnchor
    }

    func setLinkCompletions(_ candidates: [EditorLinkCompletion]) {
        pendingLinkCompletions = candidates
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.setLinkCompletions(candidates), in: webView)
        }
    }

    func setLinkPreviews(_ previews: [DocumentLinkPreview], in source: String) {
        pendingLinkPreviews = previews.prefix(DocumentPreviewCatalogBuilder.maximumLinkCount).compactMap { preview in
            guard let from = Self.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16LowerBound,
                in: source
            ), let to = Self.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16UpperBound,
                in: source
            ), to > from else { return nil }
            return MarkdownEditorLinkPreview(
                from: from,
                to: to,
                title: String(preview.title.prefix(240)),
                relationship: preview.relationship,
                fragment: preview.fragment.map { String($0.prefix(240)) },
                htmlBody: String(preview.htmlBody.prefix(24_000))
            )
        }
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setLinkPreviews(pendingLinkPreviews), in: webView)
        }
    }

    func showPreview() {
        guard canAttemptPreview, isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.showPreview, in: webView)
        }
    }

    func showPreview(at point: CGPoint) {
        guard canAttemptPreview, isReady, isLoaded, let webView,
              point.x.isFinite, point.y.isFinite else { return }
        Task {
            _ = try? await send(
                .showPreviewAt(x: point.x, y: point.y),
                in: webView
            )
        }
    }

    func setResearcherComments(_ comments: [ResearcherComment], in source: String) {
        let fingerprint = DocumentFingerprint(content: source)
        pendingResearcherComments = comments.compactMap { comment in
            let anchor = comment.anchor
            guard anchor.state == .attached,
                  anchor.fingerprint == fingerprint,
                  let from = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.lowerBound,
                    in: source
                  ),
                  let to = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.upperBound,
                    in: source
                  ),
                  to > from else { return nil }
            return MarkdownEditorCommentAnnotation(
                id: comment.id,
                from: from,
                to: to,
                comment: String(comment.text.prefix(500)),
                resolved: comment.resolvedAt != nil
            )
        }
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setResearcherComments(pendingResearcherComments), in: webView)
        }
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        let result = try await send(.queryText, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              intendedDocumentID == documentID,
              intendedFingerprint == startingFingerprint,
              self.webView === webView,
              let text = result.text else { throw SessionError.invalidResult }
        try reconcileMirror(with: text, publish: true)
        return checkedSource
    }

    /// A retained editor can be briefly unavailable while SwiftUI reattaches
    /// its WebView after a document projection changes. Saves must wait for
    /// that same session to finish loading instead of treating the transient
    /// presentation gap as loss of the authoritative CodeMirror buffer.
    func waitUntilLoadedForSave(
        maximumWait: Duration = .seconds(6)
    ) async throws -> Bool {
        if isReady, isLoaded, webView != nil { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumWait)
        while clock.now < deadline {
            try Task.checkCancellation()
            try await clock.sleep(for: .milliseconds(50))
            if isReady, isLoaded, webView != nil { return true }
        }
        return isReady && isLoaded && webView != nil
    }

    /// Captures CodeMirror's exact source, selection, and bounded history before
    /// SwiftUI removes the WKWebView during a note collapse or replacement.
    /// The retained document session replays this snapshot into the next view.
    func captureStateForViewReconstruction() async throws {
        cancelScheduledRecoveryCapture()
        let expectedKey = RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        )
        try await captureRecoverySnapshot(expectedKey: expectedKey)
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        let capturedScrollAnchor = try? await currentScrollAnchor()
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        reconstructionScrollAnchor = capturedScrollAnchor ?? pendingScrollAnchor
    }

    private func captureRecoverySnapshot(
        expectedKey: RecoveryCaptureKey
    ) async throws {
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        guard isReady, isLoaded, let webView else { return }
        let result = try await send(.captureRecovery, in: webView)
        try Task.checkCancellation()
        guard let snapshot = result.recovery,
              snapshot.documentID == documentID,
              snapshot.fingerprint == startingFingerprint,
              snapshot.generation == generation,
              snapshot.source == checkedSource,
              markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              expectedKey == RecoveryCaptureKey(
                requestEpoch: requestEpoch,
                generation: generation
              ) else {
            throw SessionError.invalidResult
        }
        recoverySnapshot = snapshot
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: snapshot.documentID,
            fingerprint: snapshot.fingerprint,
            generation: snapshot.generation,
            ranges: snapshot.ranges
        )
    }

    func currentScrollAnchor() async throws -> EditorScrollAnchor? {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let result = try await send(.queryScrollAnchor, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              self.webView === webView else {
            throw SessionError.bridgeRejected("The editor identity changed while reading its scroll position.")
        }
        return recordScrollPosition(
            result.scrollAnchor,
            fallbackFraction: result.scrollAnchor?.fallbackFraction
                ?? pendingScrollFraction
                ?? 0
        )
    }

    func queryPerformanceSamples() async throws -> [MarkdownEditorPerformanceSample] {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let result = try await send(.queryPerformance, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              self.webView === webView,
              result.accepted,
              let samples = result.performanceSamples else {
            throw SessionError.invalidResult
        }
        return samples
    }

    fileprivate func hasRecoverySnapshot(documentID: String, source: String) -> Bool {
        guard let snapshot = recoverySnapshot else { return false }
        return snapshot.documentID == documentID
            && snapshot.fingerprint == startingFingerprint
            && snapshot.generation >= 0
            && snapshot.source == source
            && markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: Self.normalizedEditorUTF16Length(of: source)
            )
    }

    func currentSelection(
        for expectedDocumentID: String? = nil,
        in source: String? = nil
    ) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        // Source and selections must come from one JS turn and one resulting
        // generation. Two separate queries can otherwise anchor a newer
        // selection into an older source after intervening input.
        let result = try await send(.queryText, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              intendedDocumentID == documentID,
              intendedFingerprint == startingFingerprint,
              self.webView === webView,
              let exactSource = result.text,
              exactSource == checkedSource,
              source == nil || source == exactSource,
              markdownEditorSelectionRangesAreValid(
                result.selections,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              let range = result.selections.first else {
            throw SessionError.invalidResult
        }
        let editorLower = min(range.anchor, range.head)
        let editorUpper = max(range.anchor, range.head)
        guard editorUpper > editorLower else { return nil }
        guard let lower = Self.sourceUTF16Offset(forEditorUTF16Offset: editorLower, in: exactSource),
              let upper = Self.sourceUTF16Offset(forEditorUTF16Offset: editorUpper, in: exactSource),
              upper > lower,
              upper - lower <= 2_000 else { throw SessionError.selectionTooLong }
        let units = exactSource.utf16
        guard let lowerUTF16 = units.index(units.startIndex, offsetBy: lower, limitedBy: units.endIndex),
              let upperUTF16 = units.index(units.startIndex, offsetBy: upper, limitedBy: units.endIndex),
              let lowerIndex = String.Index(lowerUTF16, within: exactSource),
              let upperIndex = String.Index(upperUTF16, within: exactSource) else {
            throw SessionError.invalidResult
        }
        let prefix = exactSource[..<lowerIndex]
        let excerpt = String(exactSource[lowerIndex..<upperIndex])
        let startLine = prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let endLine = startLine + excerpt.reduce(into: 0) { if $1 == "\n" { $0 += 1 } }
        return MarkdownReviewSelection(
            startLine: startLine,
            endLine: endLine,
            excerpt: excerpt,
            utf16LowerBound: lower,
            utf16UpperBound: upper,
            contextBefore: String(prefix.suffix(48)),
            contextAfter: String(exactSource[upperIndex...].prefix(48))
        )
    }

    func synchronizeCommittedText(
        expectedText: String,
        committedText: String,
        fingerprint: DocumentFingerprint,
        documentID expectedDocumentID: String
    ) async throws -> Bool {
        guard expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedFingerprint = startingFingerprint
        _ = try await send(
            .synchronizeCommittedText(
                expected: expectedText,
                committed: committedText,
                fingerprint: fingerprint.sha256
            ),
            in: webView
        )
        guard intendedRequestEpoch == requestEpoch,
              expectedDocumentID == documentID,
              intendedFingerprint == startingFingerprint,
              self.webView === webView else { return false }
        try reconcileMirror(with: committedText, publish: false)
        let rebasedRanges = currentValidSelectionRanges()
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        startingFingerprint = fingerprint.sha256
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges
        )
        // A serialized EditorState captured before commit carries the previous
        // bridge identity and may also predate line-separator reconciliation.
        // Keep an immediately recoverable exact-source fallback, then replace
        // it with a fresh bounded capture under the committed fingerprint.
        recoverySnapshot = MarkdownEditorRecoverySnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges,
            source: checkedSource,
            stateJSON: nil,
            undoHistoryPreserved: false,
            dirty: false
        )
        updatePublished(\.isDirty, to: false)
        committedTextSynchronizer?(committedText, fingerprint.sha256)
        scheduleRecoveryCapture(for: generation)
        return true
    }

    fileprivate func installCommittedTextSynchronizer(
        _ synchronizer: @escaping (String, String) -> Void
    ) {
        committedTextSynchronizer = synchronizer
    }

    fileprivate func removeCommittedTextSynchronizer() {
        committedTextSynchronizer = nil
    }

    fileprivate func installSourceChangeHandler(_ handler: @escaping (String) -> Void) {
        sourceChangeHandler = handler
    }

    fileprivate func removeSourceChangeHandler() {
        sourceChangeHandler = nil
    }

    func markClean() {
        updatePublished(\.isDirty, to: false)
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.markClean, in: webView)
        }
    }

    func focus() {
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.focus, in: webView)
        }
    }

    /// Removes keyboard focus before the retained editor is hidden by Read.
    /// The WebView remains attached so selection, undo, and CodeMirror state
    /// survive, but it must not continue accepting invisible input.
    func resignFocus() {
        guard isReady, let webView else { return }
        if let window = webView.window,
           let firstResponder = window.firstResponder as? NSView,
           firstResponder === webView || firstResponder.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
        Task {
            _ = try? await send(.blur, in: webView)
        }
    }

    func perform(_ command: MarkdownEditorCommand, argument: String? = nil) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        _ = try await send(.command(command, argument: argument), in: webView)
    }

    fileprivate func acceptEditorChanges(
        _ rawChanges: [EditorBridgeChange],
        baseGeneration: Int,
        resultingGeneration: Int
    ) -> String? {
        guard !rawChanges.isEmpty,
              rawChanges.count <= 512,
              baseGeneration == generation,
              resultingGeneration == baseGeneration + 1 else { return nil }
        let sourceBeforeChanges = checkedSource
        let usesCRLF = sourceBeforeChanges.contains("\r\n")
        var changes: [MarkdownEditorDelta] = []
        var insertedUTF16Count = 0
        var resultingEditorUTF16Length = checkedEditorUTF16Length
        for raw in rawChanges {
            guard raw.from >= 0,
                  raw.to >= raw.from,
                  raw.to <= checkedEditorUTF16Length else { return nil }
            insertedUTF16Count += raw.insert.utf16.count
            resultingEditorUTF16Length += Self.normalizedEditorUTF16Length(of: raw.insert)
                - (raw.to - raw.from)
            guard insertedUTF16Count <= 2_000_000,
                  resultingEditorUTF16Length >= 0,
                  let from = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.from,
                    in: sourceBeforeChanges
                  ),
                  let to = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.to,
                    in: sourceBeforeChanges
                  ) else { return nil }
            changes.append(MarkdownEditorDelta(
                fromUTF16: from,
                toUTF16: to,
                insertion: usesCRLF
                    ? raw.insert.replacingOccurrences(of: "\n", with: "\r\n")
                    : raw.insert
            ))
        }
        guard let nextSource = try? MarkdownEditorDeltaApplier.apply(changes, to: checkedSource) else {
            return nil
        }
        checkedSource = nextSource
        checkedEditorUTF16Length = resultingEditorUTF16Length
        generation = resultingGeneration
        updatePublished(\.isDirty, to: true)
        sourceChangeHandler?(nextSource)
        scheduleRecoveryCapture(for: resultingGeneration)
        return nextSource
    }

    fileprivate func webContentProcessTerminated() {
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        let recoveryRanges = currentValidSelectionRanges()
        if let snapshot = recoverySnapshot,
           snapshot.documentID == documentID,
           snapshot.fingerprint == startingFingerprint,
           snapshot.generation == generation,
           snapshot.source == checkedSource,
           markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
           ) {
            // The bounded serialized history may predate recent cursor moves.
            // Preserve that history while making the exact lightweight
            // selection and current dirty state authoritative for recovery.
            recoverySnapshot = MarkdownEditorRecoverySnapshot(
                documentID: snapshot.documentID,
                fingerprint: snapshot.fingerprint,
                generation: snapshot.generation,
                ranges: recoveryRanges,
                source: snapshot.source,
                stateJSON: snapshot.stateJSON,
                undoHistoryPreserved: snapshot.undoHistoryPreserved,
                dirty: isDirty
            )
        } else {
            recoverySnapshot = MarkdownEditorRecoverySnapshot(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                ranges: recoveryRanges,
                source: checkedSource,
                stateJSON: nil,
                undoHistoryPreserved: false,
                dirty: isDirty
            )
        }
        pendingSource = checkedSource
        pendingDocumentID = documentID
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
    }

    private func scheduleRecoveryCapture(for generation: Int) {
        let key = RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        )
        if scheduledRecoveryCaptureKey == key, recoveryCaptureTask != nil {
            return
        }
        recoveryCaptureTask?.cancel()
        recoveryCaptureToken &+= 1
        let token = recoveryCaptureToken
        scheduledRecoveryCaptureKey = key
        recoveryCaptureTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                guard let self else { return }
                try await self.captureRecoverySnapshot(expectedKey: key)
            } catch {
                // A newer generation, identity transition, or explicit
                // reconstruction capture owns recovery now.
            }
            guard let self, self.recoveryCaptureToken == token else { return }
            self.recoveryCaptureTask = nil
            self.scheduledRecoveryCaptureKey = nil
        }
    }

    private func flushPendingState() {
        guard isReady, let source = pendingSource, let webView else { return }
        pendingSource = nil
        let mode = pendingMode
        let documentID = pendingDocumentID
        let intendedRequestEpoch = requestEpoch
        Task {
            do {
                guard intendedRequestEpoch == requestEpoch,
                      self.documentID == documentID,
                      self.webView === webView else { return }
                let matchingRecovery = recoverySnapshot.flatMap { snapshot in
                    snapshot.documentID == documentID
                        && snapshot.fingerprint == startingFingerprint
                        && snapshot.generation >= 0
                        && snapshot.source == source
                        && markdownEditorSelectionRangesAreValid(
                            snapshot.ranges,
                            forEditorUTF16Length: checkedEditorUTF16Length
                        )
                        ? snapshot
                        : nil
                }
                checkedSource = source
                checkedEditorUTF16Length = Self.normalizedEditorUTF16Length(of: source)
                generation = 0
                _ = try await send(
                    .initialize(text: source, mode: mode, dialect: .current),
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch
                )
                _ = try await send(.setPresentationCSS(pendingPresentationCSS), in: webView, requiringRequestEpoch: intendedRequestEpoch)
                _ = try await send(.setUserCSS(pendingUserCSS), in: webView, requiringRequestEpoch: intendedRequestEpoch)
                _ = try await send(.setLinkCompletions(pendingLinkCompletions), in: webView, requiringRequestEpoch: intendedRequestEpoch)
                _ = try await send(.setLinkPreviews(pendingLinkPreviews), in: webView, requiringRequestEpoch: intendedRequestEpoch)
                _ = try await send(.setResearcherComments(pendingResearcherComments), in: webView, requiringRequestEpoch: intendedRequestEpoch)
                if let snapshot = matchingRecovery,
                   snapshot.fingerprint == startingFingerprint,
                   snapshot.source == checkedSource {
                    let recovered = try await send(
                        .restoreRecovery(snapshot),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                    guard intendedRequestEpoch == requestEpoch,
                          self.documentID == documentID,
                          self.webView === webView else { return }
                    generation = recovered.resultingGeneration
                    updatePublished(\.isDirty, to: snapshot.dirty)
                    if recovered.recovery?.undoHistoryPreserved == false {
                        updatePublished(
                            \.errorMessage,
                            to: String(localized: "The exact editor buffer was recovered, but its pre-crash undo history was unavailable.", table: "Localizable", bundle: .module)
                        )
                        _ = try await send(
                            .announceStatus(
                                "The exact editor buffer was recovered. Pre-crash undo history is unavailable."
                            ),
                            in: webView,
                            requiringRequestEpoch: intendedRequestEpoch
                        )
                    } else {
                        _ = try await send(
                            .announceStatus("The exact editor buffer was recovered."),
                            in: webView,
                            requiringRequestEpoch: intendedRequestEpoch
                        )
                    }
                } else {
                    updatePublished(\.isDirty, to: false)
                }
                // Recovery replaces the complete EditorState and can reset the
                // scroller. Apply the retained position only after restoration.
                if let anchor = pendingScrollAnchor,
                   let wireAnchor = Self.wireAnchor(from: anchor, in: checkedSource) {
                    _ = try await send(
                        .setScrollAnchor(wireAnchor),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                } else {
                    _ = try await send(
                        .setScrollFraction(pendingScrollFraction ?? 0),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                }
                guard intendedRequestEpoch == requestEpoch,
                      self.documentID == documentID,
                      self.webView === webView else { return }
                reconstructionScrollAnchor = nil
                updatePublished(\.isLoaded, to: true)
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: documentID,
                    mode: mode
                )
                flushPendingLine()
                focus()
            } catch {
                guard intendedRequestEpoch == requestEpoch,
                      self.documentID == documentID,
                      self.webView === webView else { return }
                updatePublished(\.isLoaded, to: false)
                updatePublished(\.errorMessage, to: error.localizedDescription)
            }
        }
    }

    private func flushPendingLine() {
        guard isReady, isLoaded, let line = pendingLine, let webView else { return }
        pendingLine = nil
        Task {
            _ = try? await send(.goToLine(line), in: webView)
        }
    }

    private func send(
        _ operation: MarkdownEditorOperation,
        in webView: WKWebView,
        requiringRequestEpoch requiredRequestEpoch: UInt64? = nil
    ) async throws -> MarkdownEditorCommandResult {
        let previous = requestBarrier
        let context = BridgeRequestContext(
            requestEpoch: requiredRequestEpoch ?? requestEpoch,
            sessionID: sessionID,
            documentID: documentID,
            startingFingerprint: startingFingerprint,
            generation: generation,
            webView: webView
        )
        let trackingID = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard isCurrent(context) else {
                throw SessionError.staleRequest
            }
            let request = MarkdownEditorRequest(
                sessionID: context.sessionID,
                documentID: context.documentID,
                startingFingerprint: context.startingFingerprint,
                expectedGeneration: context.generation,
                operation: operation
            )
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(request)
            guard requestData.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes + 512_000,
                  let requestJSON = String(data: requestData, encoding: .utf8) else {
                throw SessionError.invalidResult
            }
            let rawResult: Any?
            do {
                var dispatchedResult: Any?
                try await withScholiumLifecycleDeadline(
                    phase: .bridgeRequest,
                    timeout: lifecyclePolicy.bridgeRequest
                ) { [bridgeDispatcher] in
                    dispatchedResult = try await bridgeDispatcher.dispatch(
                        requestJSON: requestJSON,
                        in: webView
                    )
                }
                rawResult = dispatchedResult
            } catch {
                guard isCurrent(context) else { throw SessionError.staleRequest }
                throw error
            }
            guard isCurrent(context) else { throw SessionError.staleRequest }
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                  let resultData = try? JSONSerialization.data(withJSONObject: rawResult as Any),
                  resultData.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes + 512_000,
                  let result = try? JSONDecoder().decode(MarkdownEditorCommandResult.self, from: resultData),
                  result.requestID == request.requestID else {
                throw SessionError.invalidResult
            }
            guard result.accepted else {
                throw SessionError.bridgeRejected(result.error ?? "The Markdown editor rejected the request.")
            }
            let maximumAcceptedGeneration: Int
            if case let .restoreRecovery(snapshot) = operation {
                maximumAcceptedGeneration = snapshot.generation
            } else {
                maximumAcceptedGeneration = request.expectedGeneration + (result.sourceChanged ? 1 : 0)
            }
            guard result.resultingGeneration >= request.expectedGeneration,
                  result.resultingGeneration <= maximumAcceptedGeneration,
                  result.resultingGeneration >= generation else {
                throw SessionError.invalidResult
            }
            let generationBeforeApplyingResult = generation
            if result.sourceChanged {
                guard let text = result.text else { throw SessionError.invalidResult }
                if result.resultingGeneration > generationBeforeApplyingResult {
                    try reconcileMirror(with: text, publish: true)
                } else if text != checkedSource {
                    throw SessionError.invalidResult
                }
            }
            guard markdownEditorSelectionRangesAreValid(
                result.selections,
                forEditorUTF16Length: checkedEditorUTF16Length
            ), result.context?.selections == nil || result.context?.selections == result.selections else {
                throw SessionError.invalidResult
            }
            generation = result.resultingGeneration
            updateInteraction(
                selections: result.selections,
                line: line,
                column: column,
                lineCount: lineCount,
                documentVersion: result.resultingGeneration,
                context: result.context
            )
            if result.sourceChanged,
               result.resultingGeneration > generationBeforeApplyingResult {
                scheduleRecoveryCapture(for: result.resultingGeneration)
            }
            return result
        }
        inFlightRequestTasks[trackingID] = task
        requestBarrier = Task { @MainActor in _ = try? await task.value }
        defer { inFlightRequestTasks[trackingID] = nil }
        return try await task.value
    }

    private func isCurrent(_ context: BridgeRequestContext) -> Bool {
        context.requestEpoch == requestEpoch
            && context.sessionID == sessionID
            && context.documentID == documentID
            && context.startingFingerprint == startingFingerprint
            && context.generation == generation
            && self.webView === context.webView
    }

    #if DEBUG
    private func installQATerminationObserverIfEnabled() {
        guard !qaTerminationObserverInstalled,
              Bundle.main.bundleIdentifier == "com.scholium.qa",
              ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults") else {
            return
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveQATerminationNotification(_:)),
            name: Self.qaTerminationNotification,
            object: nil
        )
        qaTerminationObserverInstalled = true
    }

    private func removeQATerminationObserver() {
        guard qaTerminationObserverInstalled else { return }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Self.qaTerminationNotification,
            object: nil
        )
        qaTerminationObserverInstalled = false
    }

    @objc private func receiveQATerminationNotification(_ notification: Notification) {
        guard notification.userInfo?["documentID"] as? String == documentID else { return }
        guard testingSimulateWebContentProcessTermination() else { return }
        if let markerPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_UI_TEST_EDITOR_FAULT_MARKER"
        ] {
            try? Data(documentID.utf8).write(
                to: URL(fileURLWithPath: markerPath),
                options: .atomic
            )
        }
    }
    #else
    private func installQATerminationObserverIfEnabled() {}
    private func removeQATerminationObserver() {}
    #endif

    private func invalidateRequestQueue() {
        requestEpoch &+= 1
        requestBarrier?.cancel()
        requestBarrier = nil
        for task in inFlightRequestTasks.values {
            task.cancel()
        }
        inFlightRequestTasks.removeAll()
    }

    private func cancelScheduledRecoveryCapture() {
        recoveryCaptureToken &+= 1
        recoveryCaptureTask?.cancel()
        recoveryCaptureTask = nil
        scheduledRecoveryCaptureKey = nil
    }

    private func fallbackSelectionSnapshot() -> MarkdownEditorSelectionSnapshot {
        MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: [MarkdownEditorSelectionRange(anchor: 0, head: 0)]
        )
    }

    private func currentValidSelectionRanges() -> [MarkdownEditorSelectionRange] {
        if let snapshot = lastKnownSelectionSnapshot,
           snapshot.isValid(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                editorUTF16Length: checkedEditorUTF16Length
           ) {
            return snapshot.ranges
        }
        if let snapshot = recoverySnapshot,
           snapshot.documentID == documentID,
           snapshot.fingerprint == startingFingerprint,
           snapshot.generation == generation,
           snapshot.source == checkedSource,
           markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
           ) {
            return snapshot.ranges
        }
        return fallbackSelectionSnapshot().ranges
    }

    private func updatePublished<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<MarkdownEditorSession, Value>,
        to value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    private func reconcileMirror(with text: String, publish: Bool) throws {
        guard text != checkedSource else { return }
        let replacement = MarkdownEditorDelta(
            fromUTF16: 0,
            toUTF16: checkedSource.utf16.count,
            insertion: text
        )
        checkedSource = try MarkdownEditorDeltaApplier.apply([replacement], to: checkedSource)
        checkedEditorUTF16Length = Self.normalizedEditorUTF16Length(of: checkedSource)
        if publish { sourceChangeHandler?(checkedSource) }
    }

    private static func normalizedEditorUTF16Length(of source: String) -> Int {
        let units = source.utf16
        var index = units.startIndex
        var length = 0
        while index < units.endIndex {
            if units[index] == 13 {
                let next = units.index(after: index)
                if next < units.endIndex, units[next] == 10 {
                    index = units.index(after: next)
                    length += 1
                    continue
                }
            }
            index = units.index(after: index)
            length += 1
        }
        return length
    }

    private static func sourceUTF16Offset(
        forEditorUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        guard requestedOffset >= 0 else { return nil }
        let units = Array(source.utf16)
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < units.count, editorOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        guard editorOffset == requestedOffset else { return nil }
        return sourceOffset
    }

    private static func editorUTF16Offset(
        forSourceUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        let units = Array(source.utf16)
        guard requestedOffset >= 0, requestedOffset <= units.count else { return nil }
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                guard sourceOffset + 2 <= requestedOffset else { return nil }
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        return editorOffset
    }

    private static func wireAnchor(
        from anchor: EditorScrollAnchor,
        in source: String
    ) -> MarkdownEditorWireScrollAnchor? {
        guard anchor.sourceFingerprint == DocumentFingerprint(content: source).sha256,
              anchor.isValid(forUTF16Length: source.utf16.count),
              let sourceOffset = editorUTF16Offset(
                forSourceUTF16Offset: anchor.sourceUTF16Offset,
                in: source
              ),
              let lowerBound = editorUTF16Offset(
                forSourceUTF16Offset: anchor.blockUTF16LowerBound,
                in: source
              ),
              let upperBound = editorUTF16Offset(
                forSourceUTF16Offset: anchor.blockUTF16UpperBound,
                in: source
              ) else { return nil }
        return MarkdownEditorWireScrollAnchor(
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: anchor.relativeBlockPosition,
            fallbackFraction: anchor.fallbackFraction
        )
    }
}

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let source: String
    let mode: NotePresentationMode
    let presentationCSS: String
    let userCSS: String
    let linkCompletions: [EditorLinkCompletion]
    let linkPreviews: [DocumentLinkPreview]
    let researcherComments: [ResearcherComment]
    let initialScrollFraction: Double
    let initialScrollAnchor: EditorScrollAnchor?
    let onDocumentChange: (String) -> Void
    let onRequestSave: () -> Void
    let onRequestSearch: () -> Void
    let onRequestComment: () -> Void
    let onLinkActivation: (String) -> Void
    let onCommentActivation: ((UUID) -> Void)?
    let onScrollFractionChange: (Double) -> Void
    let onScrollAnchorChange: (EditorScrollAnchor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            onDocumentChange: onDocumentChange,
            onRequestSave: onRequestSave,
            onRequestSearch: onRequestSearch,
            onLinkActivation: onLinkActivation,
            onCommentActivation: onCommentActivation,
            onScrollFractionChange: onScrollFractionChange,
            onScrollAnchorChange: onScrollAnchorChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scholium")
        contentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
                window.webkit.messageHandlers.scholium.postMessage({
                    type: 'editorError',
                    message: event.message || 'The Markdown editor could not start.'
                });
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if !ScholiumMathAssets.runtimeJavaScript.isEmpty {
            contentController.addUserScript(WKUserScript(
                source: ScholiumMathAssets.runtimeJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if let editorScript = Self.editorScript {
            contentController.addUserScript(WKUserScript(
                source: editorScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        contentController.addUserScript(WKUserScript(
            source: """
            window.webkit.messageHandlers.scholium.postMessage({
                type: 'documentEnded',
                editorReady: typeof window.scholiumEditor === 'object'
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WindowAttachedWebView(frame: .zero, configuration: configuration)
        webView.editorSession = session
        webView.onRequestComment = onRequestComment
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.documentID = documentID
        context.coordinator.source = source
        context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
        context.coordinator.mode = mode
        context.coordinator.presentationCSS = presentationCSS
        context.coordinator.userCSS = userCSS
        context.coordinator.linkCompletions = linkCompletions
        context.coordinator.linkPreviews = linkPreviews
        context.coordinator.researcherComments = researcherComments
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        session.setPresentationCSS(presentationCSS)
        session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        session.attach(webView)

        guard let editorHTML = Self.editorHTML,
              Self.editorScript != nil else {
            session.reportError(String(localized: "The bundled Markdown editor resources could not be found.", table: "Localizable", bundle: .module))
            return webView
        }
        context.coordinator.awaitingEditorLoad = true
        webView.onFirstWindowAttachment = { [weak webView] in
            webView?.loadHTMLString(editorHTML, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = session
            webView.onRequestComment = onRequestComment
        }
        context.coordinator.onDocumentChange = onDocumentChange
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onRequestSearch = onRequestSearch
        context.coordinator.onLinkActivation = onLinkActivation
        context.coordinator.onCommentActivation = onCommentActivation
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        context.coordinator.onScrollAnchorChange = onScrollAnchorChange
        context.coordinator.initialScrollFraction = initialScrollFraction
        context.coordinator.initialScrollAnchor = initialScrollAnchor
        if context.coordinator.presentationCSS != presentationCSS {
            context.coordinator.presentationCSS = presentationCSS
            session.setPresentationCSS(presentationCSS)
        }
        if context.coordinator.userCSS != userCSS {
            context.coordinator.userCSS = userCSS
            session.setUserCSS(userCSS)
        }
        if context.coordinator.linkCompletions != linkCompletions {
            context.coordinator.linkCompletions = linkCompletions
            session.setLinkCompletions(linkCompletions)
        }
        if context.coordinator.linkPreviews != linkPreviews {
            context.coordinator.linkPreviews = linkPreviews
            session.setLinkPreviews(linkPreviews, in: source)
        }
        if context.coordinator.researcherComments != researcherComments {
            context.coordinator.researcherComments = researcherComments
            session.setResearcherComments(researcherComments, in: source)
        }
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.source != source {
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollPosition(anchor: initialScrollAnchor, fallbackFraction: initialScrollFraction)
        } else if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = nil
            webView.onRequestComment = nil
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
        webView.navigationDelegate = nil
        coordinator.session.removeCommittedTextSynchronizer()
        coordinator.session.removeSourceChangeHandler()
        coordinator.session.detach(webView)
    }

    private static var editorResourceDirectory: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourceURL
                .appendingPathComponent("Scholium_ScholiumApp.bundle", isDirectory: true)
            if let packagedResources = Bundle(url: packagedBundleURL)?.resourceURL,
               FileManager.default.fileExists(
                   atPath: packagedResources.appendingPathComponent("editor.bundle.js").path
               ) {
                return packagedResources
            }
        }
        return Bundle.module.url(forResource: "index", withExtension: "html")?
            .deletingLastPathComponent()
    }

    private static var editorScript: String? {
        guard let directory = editorResourceDirectory else { return nil }
        return try? String(
            contentsOf: directory.appendingPathComponent("editor.bundle.js"),
            encoding: .utf8
        )
    }

    static var editorHTML: String? {
        guard let directory = editorResourceDirectory,
              let css = try? String(
                contentsOf: directory.appendingPathComponent("editor.css"),
                encoding: .utf8
              ),
              !ScholiumCalloutStyles.css.isEmpty else { return nil }
        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src data:; font-src data:">
            <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)\n\(ScholiumTableStyles.css)\n\(ScholiumFootnoteStyles.css)\n\(ScholiumMathAssets.css)\n\(ScholiumPreviewStyles.css)\n\(ScholiumWebDesignTokens.documentPresentationCSS)</style>
            <style id="scholium-presentation-css"></style>
            <style id="scholium-user-css"></style>
          </head>
          <body><main id="editor"></main></body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: MarkdownEditorSession
        var onDocumentChange: (String) -> Void
        var onRequestSave: () -> Void
        var onRequestSearch: () -> Void
        var onLinkActivation: (String) -> Void
        var onCommentActivation: ((UUID) -> Void)?
        var onScrollFractionChange: (Double) -> Void
        var onScrollAnchorChange: (EditorScrollAnchor) -> Void
        var documentID = ""
        var source = ""
        var mode: NotePresentationMode = .livePreview
        var presentationCSS = ""
        var userCSS = ""
        var linkCompletions: [EditorLinkCompletion] = []
        var linkPreviews: [DocumentLinkPreview] = []
        var researcherComments: [ResearcherComment] = []
        var awaitingEditorLoad = false
        var recoveringAfterTermination = false
        var startingFingerprint = ""
        var lastDocumentVersion = 0
        var initialScrollFraction: Double = 0
        var initialScrollAnchor: EditorScrollAnchor?
        private var hasSignaledReady = false

        init(
            session: MarkdownEditorSession,
            onDocumentChange: @escaping (String) -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestSearch: @escaping () -> Void,
            onLinkActivation: @escaping (String) -> Void,
            onCommentActivation: ((UUID) -> Void)?,
            onScrollFractionChange: @escaping (Double) -> Void,
            onScrollAnchorChange: @escaping (EditorScrollAnchor) -> Void
        ) {
            self.session = session
            self.onDocumentChange = onDocumentChange
            self.onRequestSave = onRequestSave
            self.onRequestSearch = onRequestSearch
            self.onLinkActivation = onLinkActivation
            self.onCommentActivation = onCommentActivation
            self.onScrollFractionChange = onScrollFractionChange
            self.onScrollAnchorChange = onScrollAnchorChange
            super.init()
            session.installCommittedTextSynchronizer { [weak self] source, fingerprint in
                guard let self else { return }
                self.source = source
                self.startingFingerprint = fingerprint
            }
            session.installSourceChangeHandler { [weak self] source in
                guard let self else { return }
                self.source = source
                self.onDocumentChange(source)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium",
                  JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  data.count <= markdownEditorMaximumInboundBytes,
                  let payload = try? JSONDecoder().decode(EditorBridgeMessage.self, from: data) else { return }

            switch payload.type {
            case "ready":
                signalReady()
            case "documentEnded":
                if payload.editorReady == true {
                    signalReady()
                } else {
                    session.reportError(String(localized: "The Markdown editor script did not initialize.", table: "Localizable", bundle: .module))
                }
            case "editorError":
                session.reportError(payload.message ?? "The Markdown editor could not start.")
            case "interactionChanged":
                guard validEnvelope(payload),
                      let selections = payload.selections,
                      let line = payload.line,
                      let column = payload.column,
                      let lineCount = payload.lineCount,
                      let documentVersion = payload.documentVersion else { return }
                session.updateInteraction(
                    selections: selections,
                    line: line,
                    column: column,
                    lineCount: lineCount,
                    documentVersion: documentVersion,
                    context: payload.context
                )
            case "documentChanged":
                guard validEnvelope(payload, allowingFutureVersion: true) else { return }
                applyEditorChanges(from: payload)
            case "requestSave":
                guard validEnvelope(payload) else { return }
                onRequestSave()
            case "requestSearch":
                guard validEnvelope(payload) else { return }
                onRequestSearch()
            case "linkActivated":
                guard validEnvelope(payload), let target = payload.target, !target.isEmpty else { return }
                onLinkActivation(target)
            case "commentActivated":
                guard validEnvelope(payload),
                      let rawID = payload.commentID,
                      let id = UUID(uuidString: rawID) else { return }
                onCommentActivation?(id)
            case "scrollChanged":
                guard validEnvelope(payload),
                      let fraction = payload.scrollFraction,
                      fraction.isFinite,
                      (0...1).contains(fraction) else { return }
                if let anchor = session.recordScrollPosition(
                    payload.scrollAnchor,
                    fallbackFraction: fraction
                ) {
                    onScrollAnchorChange(anchor)
                } else {
                    session.recordScrollFraction(fraction)
                }
                onScrollFractionChange(fraction)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The page and an injected end-of-document script both report
            // readiness. Keep this delegate as a last-resort signal on beta
            // WebKit builds that occasionally drop the first script message.
            guard awaitingEditorLoad else { return }
            awaitingEditorLoad = false
            signalReady()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            session.reportError(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            session.webContentProcessTerminated()
            recoveringAfterTermination = true
            hasSignaledReady = false
            awaitingEditorLoad = true
            guard let editorHTML = MarkdownEditorWebView.editorHTML else {
                session.reportError(String(localized: "The Markdown editor resources could not be reloaded.", table: "Localizable", bundle: .module))
                return
            }
            webView.loadHTMLString(editorHTML, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Only Scholium can initiate this in-memory first navigation; the
            // view has not exposed any interactive document yet.
            if awaitingEditorLoad {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func signalReady() {
            guard !hasSignaledReady else { return }
            hasSignaledReady = true
            let preservesRetainedSession = recoveringAfterTermination
                || session.hasRecoverySnapshot(documentID: documentID, source: source)
            session.loadDocument(
                source,
                documentID: documentID,
                mode: mode,
                preservingRecovery: preservesRetainedSession
            )
            recoveringAfterTermination = false
            session.editorBecameReady()
            session.setPresentationCSS(presentationCSS)
            session.setUserCSS(userCSS)
            session.setLinkCompletions(linkCompletions)
            session.setLinkPreviews(linkPreviews, in: source)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollPosition(
                anchor: session.retainedScrollAnchor ?? initialScrollAnchor,
                fallbackFraction: session.retainedScrollFraction(
                    fallback: initialScrollFraction
                )
            )
        }

        private func validEnvelope(
            _ payload: EditorBridgeMessage,
            allowingFutureVersion: Bool = false
        ) -> Bool {
            guard payload.protocolVersion == markdownEditorProtocolVersion,
                  payload.sessionID == session.sessionID.uuidString,
                  payload.documentID == documentID,
                  payload.startingFingerprint == startingFingerprint,
                  let version = payload.documentVersion else { return false }
            return allowingFutureVersion
                ? version >= session.generation
                : version == session.generation
        }

        private func applyEditorChanges(from payload: EditorBridgeMessage) {
            guard let rawChanges = payload.changes,
                  let baseGeneration = payload.baseGeneration,
                  let resultingGeneration = payload.resultingGeneration,
                  payload.documentVersion == resultingGeneration,
                  let nextSource = session.acceptEditorChanges(
                    rawChanges,
                    baseGeneration: baseGeneration,
                    resultingGeneration: resultingGeneration
                  ) else { return }
            source = nextSource
            lastDocumentVersion = resultingGeneration
        }
    }
}
