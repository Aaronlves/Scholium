import AppKit

/// Native presentation only. The reader admits commands and owns the selected
/// tool; the native host owns placement and PDFView owns scrolling clearance.
@MainActor
final class PDFReaderFloatingToolsView: NSGlassEffectView {
    private weak var controller: PDFReaderController?
    private let canPresent: @MainActor () -> Bool
    private let stack = NSStackView()
    private let choices: [(tool: PDFReaderController.Tool, button: NSButton)]
    private let zoom: PDFReaderNativeMenuButton
    private let symbols = NSImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
    private let selectedSymbols = NSImage.SymbolConfiguration(
        pointSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold, scale: .medium)
    private var isInvalidated = false

    init(controller: PDFReaderController, canPresent: @escaping @MainActor () -> Bool) {
        self.controller = controller
        self.canPresent = canPresent
        choices = [(.select, PDFReaderToolbarButton()), (.highlight, PDFReaderToolbarButton()), (.comment, PDFReaderToolbarButton())]
        zoom = PDFReaderNativeMenuButton(controller: controller, kind: .zoom, canPresent: canPresent)
        super.init(frame: .zero)
        style = .regular
        if #available(macOS 27.0, *) { effectIsInteractive = true }
        setAccessibilityElement(false)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityIdentifier("scholium.pdf.tools")
        stack.setAccessibilityLabel(ScholiumL10n.string("PDF Reader"))
        stack.setAccessibilityRole(.group)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = ScholiumMetrics.PDFReader.toolsGap
        let inset = ScholiumMetrics.PDFReader.toolsContentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        for (index, choice) in choices.enumerated() {
            let title: String
            let symbol: String
            switch choice.tool {
            case .select: (title, symbol) = ("Select", "text.cursor")
            case .highlight: (title, symbol) = ("Highlight", "highlighter")
            case .comment: (title, symbol) = ("Comment", "text.bubble")
            }
            let button = choice.button
            button.tag = index
            button.setButtonType(.pushOnPushOff)
            button.isBordered = false
            button.image = ScholiumNativeToolbarPresentation.symbol(named: symbol)
            button.symbolConfiguration = symbols
            button.imagePosition = .imageOnly
            button.controlSize = .regular
            button.toolTip = ScholiumL10n.dynamicString(title)
            button.setAccessibilityLabel(ScholiumL10n.dynamicString(title))
            button.setAccessibilityIdentifier("scholium.pdf.tool.\(choice.tool.rawValue)")
            button.target = self
            button.action = #selector(chooseTool(_:))
            button.widthAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
            stack.addArrangedSubview(button)
        }
        zoom.controlSize = .regular
        zoom.symbolConfiguration = symbols
        zoom.widthAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
        zoom.heightAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
        stack.addArrangedSubview(zoom)
        contentView = stack
        setAccessibilityChildren([stack])
        update(controller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only PDF tools") }

    override var intrinsicContentSize: NSSize { stack.fittingSize }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        if cornerRadius != radius { cornerRadius = radius }
    }

    func update(_ controller: PDFReaderController) {
        guard !isInvalidated else { return }
        self.controller = controller
        isHidden = controller.document == nil || !controller.isVisible || !canPresent()
        setAccessibilityHidden(isHidden)
        for choice in choices {
            choice.button.isEnabled = canPresent() && controller.canSelectTool(choice.tool)
            choice.button.state = controller.tool == choice.tool ? .on : .off
            choice.button.contentTintColor = choice.button.state == .on ? .controlAccentColor : .labelColor
            choice.button.symbolConfiguration = choice.button.state == .on ? selectedSymbols : symbols
        }
        zoom.update(controller: controller)
    }

    func cancelTracking() { zoom.menu?.cancelTracking() }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        cancelTracking()
        zoom.invalidate()
        controller = nil
        isHidden = true
        setAccessibilityHidden(true)
        for choice in choices {
            choice.button.target = nil
            choice.button.action = nil
            choice.button.isEnabled = false
        }
    }

    @objc private func chooseTool(_ sender: NSButton) {
        guard !isInvalidated, canPresent(), choices.indices.contains(sender.tag),
            choices[sender.tag].button === sender, let controller
        else { return }
        controller.selectTool(choices[sender.tag].tool)
        update(controller)
    }
}
