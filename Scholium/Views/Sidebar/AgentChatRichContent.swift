import AppKit
import ScholiumContracts
import SwiftUI

/// Ranges refer to the same native rendered reply used by quotation validation.
struct AgentChatRichSegment: Identifiable {
  let id: Int
  var range: NSRange
  var columns: Int = 0
  var code: String?
  var language: String?
  var isObject: Bool { columns > 0 || code != nil }

  static func collect(_ layout: AgentChatSelectableText.Layout) -> [Self] {
    var segments: [Self] = []
    for item in layout.blocks {
      var segment = Self(id: item.block.id, range: item.range)
      switch item.block.kind {
      case .tableRow: segment.columns = item.block.cells.count
      case .code:
        segment.code = String(item.block.text.characters)
        segment.language = item.block.language
      default: break
      }
      if let last = segments.last,
        (!last.isObject && !segment.isObject || last.columns > 0 && segment.columns > 0) {
        segments[segments.count - 1].range = NSUnionRange(last.range, segment.range)
        segments[segments.count - 1].columns = max(last.columns, segment.columns)
      } else { segments.append(segment) }
    }
    return segments
  }
}

struct AgentChatRichContent: View {
  let source: String
  let quote: ((AgentChatReplySelection) -> Void)?
  let openLink: (URL) -> Void
  var onlySegment: Int? = nil
  var expandedDiagramSize: CGSize? = nil
  @State private var diagramSizes: [Int: CGSize] = [:]

  var body: some View {
    let layout = AgentChatSelectableText.layoutReply(source)
    VStack(alignment: .leading, spacing: 12) {
      ForEach(AgentChatRichSegment.collect(layout).filter { onlySegment == nil || $0.id == onlySegment }) { segment in
        if segment.isObject {
          if onlySegment == nil && segment.language?.lowercased() != "mermaid" { GroupBox { objectContent(segment, layout: layout) } }
          else { objectContent(segment, layout: layout) }
        } else { nativeText(segment, layout: layout) }
      }
    }
  }

  private func objectContent(_ segment: AgentChatRichSegment, layout: AgentChatSelectableText.Layout) -> some View {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                if onlySegment == nil && segment.language?.lowercased() != "mermaid" {
                  Text(segment.columns > 0 ? String(localized: "Table") : segment.language ?? String(localized: "Code"))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(segment.code ?? layout.text.attributedSubstring(from: segment.range).string, forType: .string)
                } label: { Image(systemName: "doc.on.doc").chatAccessory() }
                  .help("Copy").accessibilityLabel("Copy")
                if onlySegment == nil {
                  Button {
                    let natural = naturalSize(segment, layout: layout)
                    let content = AgentChatRichContent(source: source, quote: nil, openLink: openLink,
                      onlySegment: segment.id, expandedDiagramSize: diagramSizes[segment.id])
                    AgentChatRichWindowController.present(content: content, naturalSize: natural)
                  } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").chatAccessory() }
                    .help("Open in Window").accessibilityLabel("Open in Window")
                }
              }.buttonStyle(.borderless)
              if segment.language?.lowercased() == "mermaid", let code = segment.code {
                AgentChatDiagram(source: "```mermaid\n" + code + "\n```", onSize: { diagramSizes[segment.id] = $0 })
                  .frame(height: onlySegment == nil ? 120 : max(80, (expandedDiagramSize?.height ?? 160) + 24))
              } else { textSegment(segment, layout: layout) }
            }
  }

  private func nativeText(_ segment: AgentChatRichSegment, layout: AgentChatSelectableText.Layout) -> some View {
    AgentChatAttributedText(text: layout.text.attributedSubstring(from: segment.range),
      quote: quote.map { action in { range, _ in
        action(.init(range: NSRange(location: segment.range.location + range.location, length: range.length),
                     renderedText: layout.text.string))
      } }, openLink: openLink)
  }

  private func naturalSize(_ segment: AgentChatRichSegment, layout: AgentChatSelectableText.Layout) -> CGSize {
    if segment.language?.lowercased() == "mermaid" {
      return diagramSizes[segment.id] ?? CGSize(width: 440, height: 160)
    }
    let width = textWidth(segment)
    let view = AgentChatReplyTextView()
    view.textStorage?.setAttributedString(layout.text.attributedSubstring(from: segment.range))
    return CGSize(width: width, height: view.measuredHeight(width: width))
  }

  private func textWidth(_ segment: AgentChatRichSegment) -> CGFloat {
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    let codeWidth = (segment.code ?? "").components(separatedBy: .newlines)
      .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    return max(280, CGFloat(segment.columns) * 150, codeWidth + 12)
  }

  private func textSegment(_ segment: AgentChatRichSegment, layout: AgentChatSelectableText.Layout) -> some View {
    let width = textWidth(segment)
    return ScrollView(.horizontal) {
      nativeText(segment, layout: layout).frame(width: max(280, width))
    }
  }
}

struct AgentChatAttributedText: NSViewRepresentable {
  let text: NSAttributedString
  let quote: ((NSRange, String) -> Void)?
  let openLink: (URL) -> Void
  func makeNSView(context: Context) -> AgentChatReplyTextView { AgentChatReplyTextView() }
  func updateNSView(_ view: AgentChatReplyTextView, context: Context) {
    view.quote = quote
    view.openLink = openLink
    if !view.attributedString().isEqual(to: text) { view.textStorage?.setAttributedString(text) }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatReplyTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    return CGSize(width: width, height: nsView.measuredHeight(width: width))
  }
  static func dismantleNSView(_ view: AgentChatReplyTextView, coordinator: ()) {
    view.quote = nil; view.openLink = nil
  }
}

/// Reuses the document reader's inert HTML, local Mermaid runtime and navigation guard.
struct AgentChatDiagram: View {
  let source: String
  var onSize: ((CGSize) -> Void)? = nil
  @State private var failure: String?
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var projection: Projection?
  @State private var ready = false
  private struct Projection {
    let document: NoteDocument
    let html: String
    init(_ source: String) {
      document = NoteDocument(relativePath: "Chat.md", rawContent: source)
      html = SafeMarkdownRenderer.render(document).htmlBody
    }
  }
  var body: some View {
    Group {
      if let failure {
        VStack(alignment: .leading) {
          Text(verbatim: failure).foregroundStyle(.secondary)
          Text(verbatim: source).textSelection(.enabled)
          Button("Retry") { self.failure = nil }
        }
      } else if let projection {
        SafeMarkdownReadWebView(documentID: "chat-diagram", fingerprint: projection.document.fingerprint.sha256,
          source: source, htmlBody: projection.html,
          presentationCSS: Self.presentationCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased),
          userCSS: "", onLinkClick: { _ in }, onOpenExternalURL: { _ in }, selectionSurfaceIsActive: false,
          renderingReadinessIsAcknowledged: ready,
          onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
          onRenderingReady: { ready = true }, onRenderedDiagramSize: onSize)
      } else { ProgressView("Loading…") }
    }
    .task(id: source) { failure = nil; ready = false; projection = Projection(source) }
  }
  static func presentationCSS(dark: Bool, increasedContrast: Bool) -> String {
    let name: NSAppearance.Name = increasedContrast
      ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
      : (dark ? .darkAqua : .aqua)
    var declarations = ""
    NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
      let background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
      let colors: [(String, NSColor)] = [
        ("document-background", .windowBackgroundColor), ("surface-background", .controlBackgroundColor),
        ("primary-text", .labelColor), ("secondary-text", .secondaryLabelColor),
        ("separator", .secondaryLabelColor), ("accent", .controlAccentColor)
      ]
      declarations = colors.map { key, value in
        let color = value.usingColorSpace(.sRGB) ?? background
        let alpha = color.alphaComponent
        let channels = zip([color.redComponent, color.greenComponent, color.blueComponent],
                           [background.redComponent, background.greenComponent, background.blueComponent])
          .map { Int((($0 * alpha + $1 * (1 - alpha)) * 255).rounded()) }
        return String(format: "--scholium-color-%@: #%02x%02x%02x;", key, channels[0], channels[1], channels[2])
      }.joined(separator: "\n")
    }
    return """
      :root { color-scheme: \(dark ? "dark" : "light"); \(declarations) }
      html, body { background: transparent; color: var(--scholium-color-primary-text); }
      .scholium-document { padding: 8px; margin: 0; max-width: none; font-family: system-ui; }
      .scholium-document > .scholium-mermaid { margin-block: 0; }
      .scholium-mermaid-source, .scholium-mermaid-diagnostic { font-family: system-ui; }
      .scholium-mermaid-rendered .scholium-mermaid-diagnostic { display: none; }
      """
  }

}

@MainActor
final class AgentChatRichWindowController: NSWindowController, NSWindowDelegate {
  private static var retained: AgentChatRichWindowController?
  private weak var sourceWindow: NSWindow?
  private let preferredContentSize: NSSize
  static func present<Content: View>(content: Content, naturalSize: CGSize) {
    retained?.close()
    let controller = AgentChatRichWindowController(content: content, naturalSize: naturalSize)
    retained = controller
    controller.showWindow(nil)
    controller.window?.setContentSize(controller.preferredContentSize)
    controller.window?.center()
    controller.window?.makeKeyAndOrderFront(nil)
  }
  private init<Content: View>(content: Content, naturalSize: CGSize) {
    sourceWindow = NSApp.keyWindow
    let screen = sourceWindow?.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    preferredContentSize = Self.fittedSize(naturalSize, available: screen.size)
    let window = AgentChatRichWindow(contentRect: NSRect(origin: .zero, size: preferredContentSize),
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.title = ScholiumL10n.string("Reply Content")
    window.identifier = NSUserInterfaceItemIdentifier("scholium.chat.richContentWindow")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentMinSize = NSSize(width: 360, height: 180)
    let host = NSHostingView(rootView: GeometryReader { geometry in
      ScrollView {
        content.frame(maxWidth: .infinity).frame(minHeight: max(0, geometry.size.height - 64))
          .padding(32)
      }
    })
    host.sizingOptions = []
    window.contentView = host
    super.init(window: window)
    window.delegate = self
    window.center()
  }
  static func fittedSize(_ natural: CGSize, available: CGSize) -> CGSize {
    CGSize(width: min(max(360, natural.width + 64), available.width * 0.9),
           height: min(max(180, natural.height + 112), available.height * 0.9))
  }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Code-only") }
  func windowWillClose(_ notification: Notification) {
    if sourceWindow?.isVisible == true { sourceWindow?.makeKeyAndOrderFront(nil) }
    if Self.retained === self { Self.retained = nil }
  }
}

private final class AgentChatRichWindow: NSWindow {
  override func cancelOperation(_ sender: Any?) { performClose(sender) }
}
