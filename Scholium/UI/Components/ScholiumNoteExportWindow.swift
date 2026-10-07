import AppKit
import Combine
import PDFKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private struct NoteExportPreviewKey: Hashable {
    let format: NoteExportFormat
    let style: NoteExportStyle
    let textSize: CGFloat
    let paperSize: NoteExportPaperSize
    let includeYAML: Bool
}

@MainActor
final class ScholiumNoteExportWindowController: NSWindowController, NSWindowDelegate {
    private let previewModel: NoteExportPreviewModel
    private let chrome: NoteExportChrome
    var onClose: (() -> Void)?

    init(
        document: NoteDocument, title: String,
        embeddedImages: [String: RenderedMarkdownImage], excludedRoots: [URL],
        appearance: DocumentAppearanceSettings, colorScheme: WindowColorSchemeChoice
    ) {
        let model = NoteExportPreviewModel(
            document: document, title: title, embeddedImages: embeddedImages,
            excludedRoots: excludedRoots, appearance: appearance
        )
        previewModel = model
        chrome = NoteExportChrome(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 730, height: 710),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(title) — \(ScholiumL10n.string("Export Note"))"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        ScholiumWindowAppearance.apply(colorScheme, to: window)
        window.minSize = NSSize(width: 640, height: 480)
        window.contentView = NSHostingView(rootView: NoteExportPreviewView(model: model))
        chrome.install(in: window)
        window.center()
        super.init(window: window)
        model.window = window
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        previewModel.cancel()
        chrome.invalidate()
        onClose?()
    }
}

@MainActor
private final class NoteExportPreviewModel: ObservableObject {
    let document: NoteDocument
    let title: String
    let embeddedImages: [String: RenderedMarkdownImage]
    let excludedRoots: [URL]
    let appearance: DocumentAppearanceSettings
    let citationExportIssue: NoteExportError?
    weak var window: NSWindow?

    @Published var format: NoteExportFormat = .pdf
    @Published var style: NoteExportStyle = .document
    @Published var textSize: CGFloat = 12.5
    @Published var paperSize: NoteExportPaperSize = .a4
    @Published var includeYAML = false
    @Published var allowSavedCitationText = false
    @Published private(set) var previewData: Data?
    @Published private(set) var error: String?
    @Published private(set) var isRendering = false
    @Published private(set) var isExporting = false
    private var renderedKey: NoteExportPreviewKey?

    init(
        document: NoteDocument, title: String,
        embeddedImages: [String: RenderedMarkdownImage], excludedRoots: [URL],
        appearance: DocumentAppearanceSettings
    ) {
        self.document = document
        self.title = title
        self.embeddedImages = embeddedImages
        self.excludedRoots = excludedRoots
        self.appearance = appearance
        self.citationExportIssue = NoteExportService.citationExportIssue(in: document)
        self.textSize = CGFloat(appearance.body.fontSizePoints)
    }

    var previewKey: NoteExportPreviewKey {
        .init(
            format: format, style: style, textSize: textSize,
            paperSize: paperSize, includeYAML: includeYAML)
    }

    var citationExportAllowed: Bool { citationExportIssue == nil || allowSavedCitationText }

    var formatLabel: String {
        switch format {
        case .html: "HTML"
        case .pdf: "PDF"
        case .docx: ScholiumL10n.string("Word (.docx)")
        }
    }

    func renderPreview() async {
        let key = previewKey
        isRendering = true
        error = nil
        previewData = nil
        renderedKey = nil
        do {
            let data: Data
            if key.format == .docx {
                data = try await NoteExportService.renderDOCXPreviewHTML(
                    document: document, title: title,
                    style: key.style, textSize: key.textSize, paperSize: key.paperSize,
                    appearance: appearance,
                    includeYAML: key.includeYAML,
                    embeddedImages: embeddedImages,
                    allowSavedCitationText: true
                )
            } else {
                data = try await NoteExportService.render(
                    document: document, title: title, format: key.format,
                    style: key.style, textSize: key.textSize, paperSize: key.paperSize,
                    appearance: appearance,
                    includeYAML: key.includeYAML,
                    embeddedImages: embeddedImages,
                    allowSavedCitationText: true
                )
            }
            try Task.checkCancellation()
            guard previewKey == key else { return }
            previewData = data
            renderedKey = key
        } catch is CancellationError {
            return
        } catch {
            guard previewKey == key else { return }
            self.error = error.localizedDescription
        }
        if previewKey == key { isRendering = false }
    }

    func export() async {
        guard !isRendering, !isExporting, let window else { return }
        guard citationExportAllowed else {
            error = citationExportIssue?.localizedDescription
            return
        }
        isExporting = true
        error = nil
        defer { isExporting = false }
        let key = previewKey
        let panel = NSSavePanel()
        panel.title = ScholiumL10n.string("Export Note")
        panel.prompt = ScholiumL10n.string("Export")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let ext: String
        switch key.format {
        case .html:
            ext = "html"
            panel.allowedContentTypes = [.html]
        case .pdf:
            ext = "pdf"
            panel.allowedContentTypes = [.pdf]
        case .docx:
            ext = "docx"
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        }
        panel.nameFieldStringValue = title + "." + ext
        let response = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return }
        do {
            let destination = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard
                !excludedRoots.contains(where: { root in
                    let path = root.resolvingSymlinksInPath().standardizedFileURL.path
                    return destination == path || destination.hasPrefix(path + "/")
                })
            else { throw NoteExportDestinationError.insideTriptych }
            let data: Data
            if key.format != .docx, renderedKey == key, let previewData {
                data = previewData
            } else {
                data = try await NoteExportService.render(
                    document: document, title: title, format: key.format,
                    style: key.style, textSize: key.textSize, paperSize: key.paperSize,
                    appearance: appearance,
                    includeYAML: key.includeYAML,
                    embeddedImages: embeddedImages,
                    allowSavedCitationText: allowSavedCitationText
                )
            }
            try NoteExportService.requireCitationExportAdmission(in: document, allowSavedCitationText: allowSavedCitationText)
            try data.write(to: url, options: .atomic)
            window.performClose(nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancel() {
        previewData = nil
    }

    func copyPreview() {
        guard citationExportAllowed, renderedKey == previewKey, let previewData else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch format {
        case .pdf:
            pasteboard.setData(previewData, forType: .pdf)
        case .html:
            pasteboard.setData(previewData, forType: .html)
        case .docx:
            break
        }
    }

    func printPreview() {
        guard citationExportAllowed, format == .pdf, renderedKey == previewKey,
            let previewData, let document = PDFDocument(data: previewData),
            let operation = document.printOperation(
                for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: true
            )
        else { return }
        operation.run()
    }
}

private enum NoteExportDestinationError: LocalizedError {
    case insideTriptych

    var errorDescription: String? {
        ScholiumL10n.string("Choose a location outside the Triptych for exported copies.")
    }
}

@MainActor
private final class NoteExportChrome: NSObject, NSToolbarDelegate {
    private static let suggestedTextSizes: [CGFloat] = [11, 12, 12.5, 14]

    private enum Item {
        static let format = NSToolbarItem.Identifier("note-export-format")
        static let more = NSToolbarItem.Identifier("note-export-more")
        static let export = NSToolbarItem.Identifier("note-export-save")
    }

    private let model: NoteExportPreviewModel
    private let toolbar = NSToolbar(identifier: "note-export-toolbar")
    private let accessory = NSTitlebarAccessoryViewController()
    private let styleButton = NSButton(title: "", target: nil, action: nil)
    private let optionsPopover = NSPopover()
    private var observation: AnyCancellable?
    private var formatItem: NSMenuToolbarItem?
    private var moreItem: NSMenuToolbarItem?
    private var exportItem: NSToolbarItem?
    private var exportButton: NSButton?
    private var stylePopup: NSPopUpButton?
    private var sizePopup: NSPopUpButton?
    private var paperPopup: NSPopUpButton?
    private var paperRow: NSView?

    init(model: NoteExportPreviewModel) {
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [Item.format]
        optionsPopover.behavior = .transient
        observation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func install(in window: NSWindow) {
        window.toolbar = toolbar
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 38))
        styleButton.target = self
        styleButton.action = #selector(showOptions(_:))
        styleButton.isBordered = false
        styleButton.contentTintColor = .secondaryLabelColor
        styleButton.font = .systemFont(ofSize: 13, weight: .medium)
        styleButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        styleButton.imagePosition = .imageLeading
        styleButton.setAccessibilityLabel(ScholiumL10n.string("Style and Size"))
        styleButton.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(styleButton)
        NSLayoutConstraint.activate([
            styleButton.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            styleButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        accessory.view = row
        accessory.layoutAttribute = .bottom
        accessory.automaticallyAdjustsSize = false
        if #available(macOS 26.1, *) {
            accessory.preferredScrollEdgeEffectStyle = .soft
        }
        window.addTitlebarAccessoryViewController(accessory)
        refresh()
    }

    func invalidate() {
        observation?.cancel()
        observation = nil
        optionsPopover.close()
        toolbar.delegate = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Item.format, .flexibleSpace, Item.more, Item.export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Item.format, Item.more, Item.export]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Item.format:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = ScholiumL10n.string("Format")
            item.showsIndicator = true
            formatItem = item
            return item
        case Item.more:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = ScholiumL10n.string("More Export Actions")
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: item.label)
            item.showsIndicator = false
            moreItem = item
            return item
        case Item.export:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = ScholiumL10n.string("Export")
            let button = NSButton(
                title: ScholiumL10n.string("Export"),
                target: self, action: #selector(exportNote(_:)))
            button.bezelStyle = .glass
            button.bezelColor = .controlAccentColor
            button.controlSize = .large
            button.setAccessibilityLabel(item.label)
            button.sizeToFit()
            item.view = button
            exportButton = button
            exportItem = item
            return item
        default: return nil
        }
    }

    private func refresh() {
        formatItem?.title = model.formatLabel
        formatItem?.menu = makeFormatMenu()
        moreItem?.menu = makeMoreMenu()
        let canExport = !model.isRendering && !model.isExporting && model.previewData != nil && model.citationExportAllowed
        exportItem?.isEnabled = canExport
        exportButton?.isEnabled = canExport
        let style: String
        switch model.style {
        case .document: style = ScholiumL10n.string("Match Document")
        case .apa7: style = "APA 7"
        case .mla9: style = "MLA 9"
        }
        styleButton.title =
            model.format == .html
            ? style : "\(style) · \(model.paperSize == .a4 ? "A4" : ScholiumL10n.string("US Letter"))"
        stylePopup?.selectItem(at: styleIndex)
        if let sizePopup {
            let choices = textSizeChoices
            let titles = choices.map { "\(Double($0).formatted()) pt" }
            if sizePopup.itemArray.map(\.title) != titles {
                sizePopup.removeAllItems()
                sizePopup.addItems(withTitles: titles)
            }
            sizePopup.selectItem(at: choices.firstIndex(of: model.textSize) ?? 0)
        }
        paperPopup?.selectItem(at: model.paperSize == .a4 ? 0 : 1)
        paperRow?.isHidden = model.format == .html
    }

    private var styleIndex: Int {
        switch model.style {
        case .document: 0
        case .apa7: 1
        case .mla9: 2
        }
    }

    private var textSizeChoices: [CGFloat] {
        Array(Set(Self.suggestedTextSizes + [model.textSize])).sorted()
    }

    private func menuItem(_ title: String, action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private func makeFormatMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, title) in ["HTML", "PDF", ScholiumL10n.string("Word (.docx)")].enumerated() {
            let item = menuItem(title, action: #selector(selectFormat(_:)), tag: index)
            item.state = index == formatIndex ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private var formatIndex: Int {
        switch model.format {
        case .html: 0
        case .pdf: 1
        case .docx: 2
        }
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        if model.format == .pdf {
            let print = menuItem(ScholiumL10n.string("Print…"), action: #selector(printNote(_:)))
            print.isEnabled = model.citationExportAllowed
            menu.addItem(print)
        }
        if model.format != .docx {
            let copy = menuItem(ScholiumL10n.string("Copy to Clipboard"), action: #selector(copyNote(_:)))
            copy.isEnabled = model.citationExportAllowed
            menu.addItem(copy)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let yaml = menuItem(
            ScholiumL10n.string("Include YAML metadata"), action: #selector(toggleYAML(_:)))
        yaml.state = model.includeYAML ? .on : .off
        menu.addItem(yaml)
        return menu
    }

    @objc private func selectFormat(_ sender: NSMenuItem) {
        model.format = [.html, .pdf, .docx][sender.tag]
    }

    @objc private func toggleYAML(_ sender: NSMenuItem) { model.includeYAML.toggle() }
    @objc private func printNote(_ sender: NSMenuItem) { model.printPreview() }
    @objc private func copyNote(_ sender: NSMenuItem) { model.copyPreview() }
    @objc private func exportNote(_ sender: Any?) { Task { await model.export() } }

    @objc private func showOptions(_ sender: NSButton) {
        if optionsPopover.isShown {
            optionsPopover.close()
            return
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let style = NSPopUpButton()
        style.addItems(withTitles: [ScholiumL10n.string("Match Document"), "APA 7", "MLA 9"])
        style.target = self
        style.action = #selector(selectStyle(_:))
        stylePopup = style
        stack.addArrangedSubview(optionRow(ScholiumL10n.string("Style"), popup: style))
        let size = NSPopUpButton()
        size.target = self
        size.action = #selector(selectSize(_:))
        sizePopup = size
        stack.addArrangedSubview(optionRow(ScholiumL10n.string("Text size"), popup: size))
        let paper = NSPopUpButton()
        paper.addItems(withTitles: ["A4", ScholiumL10n.string("US Letter")])
        paper.target = self
        paper.action = #selector(selectPaper(_:))
        paperPopup = paper
        let row = optionRow(ScholiumL10n.string("Page size"), popup: paper)
        paperRow = row
        stack.addArrangedSubview(row)
        let controller = NSViewController()
        controller.view = stack
        controller.preferredContentSize = NSSize(width: 310, height: 160)
        optionsPopover.contentViewController = controller
        refresh()
        optionsPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func optionRow(_ label: String, popup: NSPopUpButton) -> NSStackView {
        let text = NSTextField(labelWithString: label)
        text.textColor = .secondaryLabelColor
        text.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 155).isActive = true
        let row = NSStackView(views: [text, popup])
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        return row
    }

    @objc private func selectStyle(_ sender: NSPopUpButton) {
        model.style = [.document, .apa7, .mla9][sender.indexOfSelectedItem]
    }

    @objc private func selectSize(_ sender: NSPopUpButton) {
        let choices = textSizeChoices
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        model.textSize = choices[sender.indexOfSelectedItem]
    }

    @objc private func selectPaper(_ sender: NSPopUpButton) {
        model.paperSize = sender.indexOfSelectedItem == 0 ? .a4 : .letter
    }
}

private struct NoteExportPreviewView: View {
    @StateObject var model: NoteExportPreviewModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)
            VStack {
                Spacer()
                if let issue = model.citationExportIssue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(issue.localizedDescription)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(ScholiumL10n.string("Export Saved Text"), isOn: $model.allowSavedCitationText)
                            .toggleStyle(.checkbox)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
                if model.format == .docx {
                    Text(
                        ScholiumL10n.string(
                            "Word keeps editable text, headings, hyperlinks and footnotes; tables flatten, while images and exact line spacing are omitted."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                }
                if model.previewData != nil, let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityAddTraits(.updatesFrequently)
                        .padding(.bottom, 18)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task(id: model.previewKey) { await model.renderPreview() }
        .onChange(of: model.style) { _, style in
            model.textSize =
                style == .document
                ? CGFloat(model.appearance.body.fontSizePoints) : 12
            model.paperSize = style == .document ? .a4 : .letter
        }
    }

    private var preview: some View {
        Group {
            if let data = model.previewData {
                if model.format == .pdf {
                    ScholiumPDFExportPreview(data: data)
                } else if let html = String(data: data, encoding: .utf8) {
                    ScholiumHTMLExportPreview(html: html)
                        .background(.white)
                }
            } else if model.isRendering {
                ProgressView(ScholiumL10n.string("Preparing preview…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    ScholiumL10n.string("Preview unavailable"),
                    systemImage: "doc",
                    description: Text(model.error ?? "")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

}

private final class WidthFittingPDFView: PDFView {
    private let paperWidthFraction: CGFloat = 0.82
    private let topPageGap: CGFloat = 12

    override func layout() {
        super.layout()
        fitPageWidth()
        updateScrollInsets()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollInsets()
    }

    func fitPageWidth() {
        guard let page = document?.page(at: 0), bounds.width > 0 else { return }
        let pageWidth = page.bounds(for: .cropBox).width
        guard pageWidth > 0 else { return }
        let target = max(bounds.width * paperWidthFraction, 1) / pageWidth
        if target > maxScaleFactor { maxScaleFactor = target }
        if target < minScaleFactor { minScaleFactor = target }
        if abs(minScaleFactor - target) > 0.001 { minScaleFactor = target }
        if abs(maxScaleFactor - target) > 0.001 { maxScaleFactor = target }
        if abs(scaleFactor - target) > 0.001 { scaleFactor = target }
    }

    fileprivate func updateScrollInsets() {
        guard let window, let scrollView = documentView?.enclosingScrollView else { return }
        let scrollFrame = scrollView.convert(scrollView.bounds, to: nil)
        let titlebarOverlap = max(scrollFrame.maxY - window.contentLayoutRect.maxY, 0)
        let desiredTop = titlebarOverlap + topPageGap
        if scrollView.automaticallyAdjustsContentInsets {
            scrollView.automaticallyAdjustsContentInsets = false
        }
        guard abs(scrollView.contentInsets.top - desiredTop) > 0.5 else { return }
        var insets = scrollView.contentInsets
        insets.top = desiredTop
        scrollView.contentInsets = insets
    }
}

private struct ScholiumPDFExportPreview: NSViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WidthFittingPDFView {
        let view = WidthFittingPDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = false
        view.pageShadowsEnabled = false
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: WidthFittingPDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            view.document = PDFDocument(data: data)
        }
        view.fitPageWidth()
        view.updateScrollInsets()
    }

    final class Coordinator { var data: Data? }
}

private struct ScholiumHTMLExportPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        @MainActor func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.navigationType == .linkActivated ? .cancel : .allow
        }
    }
}
